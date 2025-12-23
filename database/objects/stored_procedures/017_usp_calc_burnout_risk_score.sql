
/****** Object:  StoredProcedure [dbo].[usp_calc_burnout_risk_score]    Script Date: 22/12/2025 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE OR ALTER PROCEDURE [dbo].[usp_calc_burnout_risk_score]
  @client_id NVARCHAR(50)
AS
BEGIN
  /*
  ================================================================================
  Procedure: usp_calc_burnout_risk_score
  Purpose:   Calculate burnout/overwork risk score for employees based on work
             pattern changes comparing baseline vs recent periods. Detects patterns
             of excessive hours, overwork, and unsustainable work patterns.
             Uses weighted scoring model with configurable thresholds.
  
  Parameters:
    @client_id - Client identifier (required)
  
  Returns:   None (inserts into report_workload table with risk_score)
  
  Multi-tenant: Yes - all operations filtered by @client_id
  Transaction:  Yes - wrapped with error handling
  ================================================================================
  */
  
  SET NOCOUNT ON;
  SET XACT_ABORT ON;
  
  -- Guard clause
  IF @client_id IS NULL OR LTRIM(RTRIM(@client_id)) = N''
  BEGIN
    RAISERROR('usp_calc_burnout_risk_score: @client_id is required.', 16, 1);
    RETURN;
  END
  
  IF NOT EXISTS (SELECT 1 FROM dbo.calc_period_metrics WHERE client_id = @client_id)
  BEGIN
    RAISERROR('No rows in calc_period_metrics for client_id=%s.', 16, 1, @client_id);
    RETURN;
  END
  
  -- ========================================================================
  -- LOAD CONFIGURABLE PARAMETERS FROM risk_config TABLE
  -- ========================================================================
  
  -- Feature weights (should sum to 100, but we'll normalize if needed)
  DECLARE
    @w_hours_increase FLOAT,
    @w_arrival_earlier FLOAT,
    @w_departure_later FLOAT,
    @w_non_workday_increase FLOAT,
    @w_sustained_presence FLOAT,
    @w_working_while_sick FLOAT,
    @w_multi_factor_bonus FLOAT;
    
  -- Threshold multipliers for hours
  DECLARE
    @hours_threshold_critical FLOAT,  -- e.g., 0.30 for 30% increase
    @hours_threshold_high FLOAT,      -- e.g., 0.20 for 20% increase
    @hours_threshold_moderate FLOAT,  -- e.g., 0.10 for 10% increase
    @hours_mult_critical FLOAT,       -- e.g., 1.5
    @hours_mult_high FLOAT,           -- e.g., 1.3
    @hours_mult_moderate FLOAT;       -- e.g., 1.1
    
  -- Threshold multipliers for arrival (earlier)
  DECLARE
    @arrival_threshold_critical INT,  -- e.g., 90 minutes earlier
    @arrival_threshold_high INT,      -- e.g., 60 minutes earlier
    @arrival_threshold_moderate INT,  -- e.g., 30 minutes earlier
    @arrival_mult_critical FLOAT,     -- e.g., 1.5
    @arrival_mult_high FLOAT,         -- e.g., 1.3
    @arrival_mult_moderate FLOAT;     -- e.g., 1.1
    
  -- Threshold multipliers for departure (later)
  DECLARE
    @departure_threshold_critical INT,  -- e.g., 90 minutes later
    @departure_threshold_high INT,      -- e.g., 60 minutes later
    @departure_threshold_moderate INT,  -- e.g., 30 minutes later
    @departure_mult_critical FLOAT,     -- e.g., 1.5
    @departure_mult_high FLOAT,         -- e.g., 1.3
    @departure_mult_moderate FLOAT;     -- e.g., 1.1
    
  -- Threshold multipliers for non-workday presence
  DECLARE
    @non_workday_threshold_critical INT,  -- e.g., 6 days
    @non_workday_threshold_high INT,      -- e.g., 4 days
    @non_workday_threshold_moderate INT,  -- e.g., 2 days
    @non_workday_mult_critical FLOAT,     -- e.g., 1.5
    @non_workday_mult_high FLOAT,         -- e.g., 1.3
    @non_workday_mult_moderate FLOAT;     -- e.g., 1.1
    
  -- Sustained presence thresholds
  DECLARE
    @presence_threshold_critical FLOAT,  -- e.g., 0.98 for 98%
    @presence_threshold_high FLOAT,      -- e.g., 0.95 for 95%
    @presence_threshold_moderate FLOAT;  -- e.g., 0.90 for 90%
    
  -- Working while sick thresholds
  DECLARE
    @working_sick_absence_threshold_high FLOAT,    -- e.g., 0.20 for 20% decrease
    @working_sick_absence_threshold_moderate FLOAT, -- e.g., 0.10 for 10% decrease
    @working_sick_hours_threshold_high FLOAT,      -- e.g., 0.10 for 10% increase
    @working_sick_hours_threshold_moderate FLOAT;  -- e.g., 0.05 for 5% increase
    
  -- Multi-factor overwork thresholds
  DECLARE
    @multi_factor_threshold_hours_pct FLOAT,
    @multi_factor_threshold_arrival_min INT,
    @multi_factor_threshold_departure_min INT,
    @multi_factor_threshold_non_workday INT,
    @multi_factor_bonus_4 FLOAT,
    @multi_factor_bonus_3 FLOAT,
    @multi_factor_bonus_2 FLOAT;
    
  -- Risk level boundaries
  DECLARE
    @risk_threshold_low INT,               -- e.g., 30
    @risk_threshold_medium INT,            -- e.g., 50
    @risk_threshold_high INT;              -- e.g., 70
    
  -- Minimum data requirements
  DECLARE
    @min_baseline_days INT,                -- e.g., 14
    @min_recent_days INT;                  -- e.g., 7
    
  -- Helper function to get config with fallback
  -- Pattern: client-specific first, then global (client_id IS NULL), then default
  
  SELECT
    -- Feature weights (defaults sum to 100)
    @w_hours_increase = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_w_hours_increase') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_w_hours_increase') AS FLOAT), 40.0),
    @w_arrival_earlier = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_w_arrival_earlier') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_w_arrival_earlier') AS FLOAT), 15.0),
    @w_departure_later = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_w_departure_later') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_w_departure_later') AS FLOAT), 15.0),
    @w_non_workday_increase = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_w_non_workday_increase') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_w_non_workday_increase') AS FLOAT), 15.0),
    @w_sustained_presence = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_w_sustained_presence') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_w_sustained_presence') AS FLOAT), 10.0),
    @w_working_while_sick = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_w_working_while_sick') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_w_working_while_sick') AS FLOAT), 5.0),
    @w_multi_factor_bonus = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_w_multi_factor_bonus') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_w_multi_factor_bonus') AS FLOAT), 10.0),
      
    -- Hours threshold multipliers
    @hours_threshold_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_hours_threshold_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_hours_threshold_critical') AS FLOAT), 0.30),
    @hours_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_hours_threshold_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_hours_threshold_high') AS FLOAT), 0.20),
    @hours_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_hours_threshold_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_hours_threshold_moderate') AS FLOAT), 0.10),
    @hours_mult_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_hours_mult_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_hours_mult_critical') AS FLOAT), 1.5),
    @hours_mult_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_hours_mult_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_hours_mult_high') AS FLOAT), 1.3),
    @hours_mult_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_hours_mult_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_hours_mult_moderate') AS FLOAT), 1.1),
      
    -- Arrival threshold multipliers
    @arrival_threshold_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_arrival_threshold_critical') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_arrival_threshold_critical') AS INT), 90),
    @arrival_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_arrival_threshold_high') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_arrival_threshold_high') AS INT), 60),
    @arrival_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_arrival_threshold_moderate') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_arrival_threshold_moderate') AS INT), 30),
    @arrival_mult_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_arrival_mult_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_arrival_mult_critical') AS FLOAT), 1.5),
    @arrival_mult_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_arrival_mult_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_arrival_mult_high') AS FLOAT), 1.3),
    @arrival_mult_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_arrival_mult_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_arrival_mult_moderate') AS FLOAT), 1.1),
      
    -- Departure threshold multipliers
    @departure_threshold_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_departure_threshold_critical') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_departure_threshold_critical') AS INT), 90),
    @departure_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_departure_threshold_high') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_departure_threshold_high') AS INT), 60),
    @departure_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_departure_threshold_moderate') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_departure_threshold_moderate') AS INT), 30),
    @departure_mult_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_departure_mult_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_departure_mult_critical') AS FLOAT), 1.5),
    @departure_mult_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_departure_mult_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_departure_mult_high') AS FLOAT), 1.3),
    @departure_mult_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_departure_mult_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_departure_mult_moderate') AS FLOAT), 1.1),
      
    -- Non-workday threshold multipliers
    @non_workday_threshold_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_non_workday_threshold_critical') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_non_workday_threshold_critical') AS INT), 6),
    @non_workday_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_non_workday_threshold_high') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_non_workday_threshold_high') AS INT), 4),
    @non_workday_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_non_workday_threshold_moderate') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_non_workday_threshold_moderate') AS INT), 2),
    @non_workday_mult_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_non_workday_mult_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_non_workday_mult_critical') AS FLOAT), 1.5),
    @non_workday_mult_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_non_workday_mult_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_non_workday_mult_high') AS FLOAT), 1.3),
    @non_workday_mult_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_non_workday_mult_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_non_workday_mult_moderate') AS FLOAT), 1.1),
      
    -- Sustained presence thresholds
    @presence_threshold_critical = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_presence_threshold_critical') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_presence_threshold_critical') AS FLOAT), 0.98),
    @presence_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_presence_threshold_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_presence_threshold_high') AS FLOAT), 0.95),
    @presence_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_presence_threshold_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_presence_threshold_moderate') AS FLOAT), 0.90),
      
    -- Working while sick thresholds
    @working_sick_absence_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_working_sick_absence_threshold_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_working_sick_absence_threshold_high') AS FLOAT), 0.20),
    @working_sick_absence_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_working_sick_absence_threshold_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_working_sick_absence_threshold_moderate') AS FLOAT), 0.10),
    @working_sick_hours_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_working_sick_hours_threshold_high') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_working_sick_hours_threshold_high') AS FLOAT), 0.10),
    @working_sick_hours_threshold_moderate = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_working_sick_hours_threshold_moderate') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_working_sick_hours_threshold_moderate') AS FLOAT), 0.05),
      
    -- Multi-factor overwork thresholds
    @multi_factor_threshold_hours_pct = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_multi_factor_threshold_hours_pct') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_multi_factor_threshold_hours_pct') AS FLOAT), 0.10),
    @multi_factor_threshold_arrival_min = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_multi_factor_threshold_arrival_min') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_multi_factor_threshold_arrival_min') AS INT), 30),
    @multi_factor_threshold_departure_min = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_multi_factor_threshold_departure_min') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_multi_factor_threshold_departure_min') AS INT), 30),
    @multi_factor_threshold_non_workday = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_multi_factor_threshold_non_workday') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_multi_factor_threshold_non_workday') AS INT), 1),
    @multi_factor_bonus_4 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_multi_factor_bonus_4') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_multi_factor_bonus_4') AS FLOAT), 10.0),
    @multi_factor_bonus_3 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_multi_factor_bonus_3') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_multi_factor_bonus_3') AS FLOAT), 6.0),
    @multi_factor_bonus_2 = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_multi_factor_bonus_2') AS FLOAT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_multi_factor_bonus_2') AS FLOAT), 3.0),
      
    -- Risk level boundaries
    @risk_threshold_low = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_threshold_low') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_threshold_low') AS INT), 30),
    @risk_threshold_medium = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_threshold_medium') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_threshold_medium') AS INT), 50),
    @risk_threshold_high = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_threshold_high') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_threshold_high') AS INT), 70),
      
    -- Minimum data requirements
    @min_baseline_days = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_min_baseline_days') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_min_baseline_days') AS INT), 14),
    @min_recent_days = COALESCE(
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id=@client_id AND config_key='burnout_risk_min_recent_days') AS INT),
      TRY_CAST((SELECT TOP(1) config_value FROM dbo.risk_config WHERE client_id IS NULL AND config_key='burnout_risk_min_recent_days') AS INT), 7);
  
  -- Normalize weights (in case they don't sum to 100)
  DECLARE @weight_sum FLOAT = @w_hours_increase + @w_arrival_earlier + @w_departure_later + 
                               @w_non_workday_increase + @w_sustained_presence + @w_working_while_sick;
  IF @weight_sum > 0
  BEGIN
    SET @w_hours_increase = @w_hours_increase * 100.0 / @weight_sum;
    SET @w_arrival_earlier = @w_arrival_earlier * 100.0 / @weight_sum;
    SET @w_departure_later = @w_departure_later * 100.0 / @weight_sum;
    SET @w_non_workday_increase = @w_non_workday_increase * 100.0 / @weight_sum;
    SET @w_sustained_presence = @w_sustained_presence * 100.0 / @weight_sum;
    SET @w_working_while_sick = @w_working_while_sick * 100.0 / @weight_sum;
  END
  
  -- ========================================================================
  -- CLEAN OLD DATA
  -- ========================================================================
  
  DELETE FROM dbo.report_workload WHERE client_id=@client_id;
  
  -- ========================================================================
  -- CALCULATE BURNOUT RISK SCORES
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#risk_calc') IS NOT NULL DROP TABLE #risk_calc;
  
  SELECT
    cpm.client_id,
    cpm.emp_id,
    CAST(cpm.baseline_start AS DATE) AS baseline_start,
    CAST(cpm.baseline_end AS DATE) AS baseline_end,
    CAST(cpm.recent_start AS DATE) AS recent_start,
    CAST(cpm.recent_end AS DATE) AS recent_end,
    cpm.workdays_b,
    cpm.workdays_r,
    cpm.presence_pct_b,
    cpm.presence_pct_r,
    cpm.absence_pct_b,
    cpm.absence_pct_r,
    cpm.avg_minutes_b,
    cpm.avg_minutes_r,
    cpm.avg_arrival_b,
    cpm.avg_arrival_r,
    cpm.avg_departure_b,
    cpm.avg_departure_r,
    cpm.non_workday_presence_b,
    cpm.non_workday_presence_r,
    
    -- Calculate deltas (BURNOUT = INCREASES in work, EARLIER arrivals, LATER departures)
    -- Hours: INCREASE (positive delta)
    CASE 
      WHEN cpm.avg_minutes_b > 0 
      THEN (cpm.avg_minutes_r - cpm.avg_minutes_b) / cpm.avg_minutes_b
      ELSE 0.0
    END AS avg_minutes_delta_pct,
    
    -- Arrival: EARLIER (negative delta in minutes: recent - baseline)
    DATEDIFF(MINUTE, CAST(cpm.avg_arrival_r AS TIME), CAST(cpm.avg_arrival_b AS TIME)) AS arrival_delta_minutes,
    
    -- Departure: LATER (positive delta in minutes: recent - baseline)
    DATEDIFF(MINUTE, CAST(cpm.avg_departure_b AS TIME), CAST(cpm.avg_departure_r AS TIME)) AS departure_delta_minutes,
    
    -- Non-workday: INCREASE (positive delta)
    CAST(cpm.non_workday_presence_r AS FLOAT) - CAST(cpm.non_workday_presence_b AS FLOAT) AS non_workday_delta,
    
    -- Absence: DECREASE for working while sick (negative delta)
    CASE 
      WHEN cpm.absence_pct_b > 0 
      THEN (cpm.absence_pct_b - cpm.absence_pct_r) / cpm.absence_pct_b
      WHEN cpm.absence_pct_r = 0 AND cpm.absence_pct_b > 0 THEN 1.0  -- Complete elimination
      ELSE 0.0
    END AS absence_delta_pct
    
  INTO #risk_calc
  FROM dbo.calc_period_metrics cpm
  WHERE cpm.client_id = @client_id
    AND cpm.workdays_b >= @min_baseline_days
    AND cpm.workdays_r >= @min_recent_days;
  
  -- ========================================================================
  -- CALCULATE RISK SCORES
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#risk_scores') IS NOT NULL DROP TABLE #risk_scores;
  
  SELECT
    rc.*,
    
    -- 1. Work Hours Increase Score (0 to @w_hours_increase)
    CASE 
      WHEN rc.avg_minutes_delta_pct > 0 
      THEN CASE 
        WHEN rc.avg_minutes_delta_pct * @w_hours_increase * 100.0 > @w_hours_increase 
        THEN @w_hours_increase
        ELSE rc.avg_minutes_delta_pct * @w_hours_increase * 100.0
      END
      ELSE 0.0
    END AS hours_risk_score,
    
    -- Hours multiplier
    CASE 
      WHEN rc.avg_minutes_delta_pct > @hours_threshold_critical THEN @hours_mult_critical
      WHEN rc.avg_minutes_delta_pct > @hours_threshold_high THEN @hours_mult_high
      WHEN rc.avg_minutes_delta_pct > @hours_threshold_moderate THEN @hours_mult_moderate
      ELSE 1.0
    END AS hours_multiplier,
    
    -- 2. Earlier Arrival Score (0 to @w_arrival_earlier)
    CASE 
      WHEN rc.arrival_delta_minutes < -@arrival_threshold_moderate  -- Negative = earlier
      THEN CASE
        WHEN ABS(rc.arrival_delta_minutes) / 60.0 * @w_arrival_earlier > @w_arrival_earlier
        THEN @w_arrival_earlier
        ELSE ABS(rc.arrival_delta_minutes) / 60.0 * @w_arrival_earlier
      END
      ELSE 0.0
    END AS arrival_risk_score,
    
    -- Arrival multiplier
    CASE 
      WHEN rc.arrival_delta_minutes < -@arrival_threshold_critical THEN @arrival_mult_critical
      WHEN rc.arrival_delta_minutes < -@arrival_threshold_high THEN @arrival_mult_high
      WHEN rc.arrival_delta_minutes < -@arrival_threshold_moderate THEN @arrival_mult_moderate
      ELSE 1.0
    END AS arrival_multiplier,
    
    -- 3. Later Departure Score (0 to @w_departure_later)
    CASE 
      WHEN rc.departure_delta_minutes > @departure_threshold_moderate  -- Positive = later
      THEN CASE
        WHEN rc.departure_delta_minutes / 60.0 * @w_departure_later > @w_departure_later
        THEN @w_departure_later
        ELSE rc.departure_delta_minutes / 60.0 * @w_departure_later
      END
      ELSE 0.0
    END AS departure_risk_score,
    
    -- Departure multiplier
    CASE 
      WHEN rc.departure_delta_minutes > @departure_threshold_critical THEN @departure_mult_critical
      WHEN rc.departure_delta_minutes > @departure_threshold_high THEN @departure_mult_high
      WHEN rc.departure_delta_minutes > @departure_threshold_moderate THEN @departure_mult_moderate
      ELSE 1.0
    END AS departure_multiplier,
    
    -- 4. Non-Workday Presence Increase Score (0 to @w_non_workday_increase)
    CASE 
      WHEN rc.non_workday_delta > 0
      THEN CASE
        WHEN (rc.non_workday_delta / 5.0) * @w_non_workday_increase > @w_non_workday_increase
        THEN @w_non_workday_increase
        ELSE (rc.non_workday_delta / 5.0) * @w_non_workday_increase
      END
      ELSE 0.0
    END AS non_workday_risk_score,
    
    -- Non-workday multiplier
    CASE 
      WHEN rc.non_workday_delta >= @non_workday_threshold_critical THEN @non_workday_mult_critical
      WHEN rc.non_workday_delta >= @non_workday_threshold_high THEN @non_workday_mult_high
      WHEN rc.non_workday_delta >= @non_workday_threshold_moderate THEN @non_workday_mult_moderate
      ELSE 1.0
    END AS non_workday_multiplier,
    
    -- 5. Sustained High Presence Score (0 to @w_sustained_presence)
    CASE 
      WHEN rc.presence_pct_r >= @presence_threshold_moderate AND rc.presence_pct_r >= rc.presence_pct_b
      THEN CASE
        WHEN rc.presence_pct_r >= @presence_threshold_critical THEN @w_sustained_presence
        WHEN rc.presence_pct_r >= @presence_threshold_high THEN @w_sustained_presence * 0.7
        ELSE @w_sustained_presence * 0.4
      END
      ELSE 0.0
    END AS sustained_presence_score,
    
    -- 6. Working While Sick Pattern Score (0 to @w_working_while_sick)
    CASE 
      WHEN rc.absence_delta_pct > @working_sick_absence_threshold_high 
           AND rc.avg_minutes_delta_pct > @working_sick_hours_threshold_high
      THEN @w_working_while_sick
      WHEN rc.absence_delta_pct > @working_sick_absence_threshold_moderate 
           AND rc.avg_minutes_delta_pct > @working_sick_hours_threshold_moderate
      THEN @w_working_while_sick * 0.6
      ELSE 0.0
    END AS working_while_sick_score,
    
    -- Count overwork factors for multi-factor bonus
    CASE WHEN rc.avg_minutes_delta_pct > @multi_factor_threshold_hours_pct THEN 1 ELSE 0 END +
    CASE WHEN rc.arrival_delta_minutes < -@multi_factor_threshold_arrival_min THEN 1 ELSE 0 END +
    CASE WHEN rc.departure_delta_minutes > @multi_factor_threshold_departure_min THEN 1 ELSE 0 END +
    CASE WHEN rc.non_workday_delta > @multi_factor_threshold_non_workday THEN 1 ELSE 0 END +
    CASE WHEN rc.presence_pct_r >= @presence_threshold_moderate AND rc.presence_pct_r >= rc.presence_pct_b THEN 1 ELSE 0 END AS overwork_factors
    
  INTO #risk_scores
  FROM #risk_calc rc;
  
  -- ========================================================================
  -- CALCULATE FINAL RISK SCORES WITH MULTIPLIERS AND BONUSES
  -- ========================================================================
  
  IF OBJECT_ID('tempdb..#final_risk') IS NOT NULL DROP TABLE #final_risk;
  
  SELECT
    rs.*,
    
    -- Multi-factor bonus
    CASE
      WHEN rs.overwork_factors >= 4 THEN @multi_factor_bonus_4
      WHEN rs.overwork_factors >= 3 THEN @multi_factor_bonus_3
      WHEN rs.overwork_factors >= 2 THEN @multi_factor_bonus_2
      ELSE 0.0
    END AS multi_factor_bonus,
    
    -- Base score with multipliers
    (rs.hours_risk_score * rs.hours_multiplier) +
    (rs.arrival_risk_score * rs.arrival_multiplier) +
    (rs.departure_risk_score * rs.departure_multiplier) +
    (rs.non_workday_risk_score * rs.non_workday_multiplier) +
    rs.sustained_presence_score +
    rs.working_while_sick_score AS base_score
    
  INTO #final_risk
  FROM #risk_scores rs;
  
  -- ========================================================================
  -- INSERT INTO report_workload TABLE
  -- ========================================================================
  
  INSERT INTO dbo.report_workload
  (
    client_id,
    emp_id,
    department,
    emp_role,
    site_name,
    risk_score,
    risk_type,
    score_explanation,
    computed_at
  )
  SELECT
    fr.client_id,
    fr.emp_id,
    ISNULL(vd.department, N'Not Reported') AS department,
    ISNULL(vr.emp_role, N'Not Reported') AS emp_role,
    ISNULL(vs.site_name, N'') AS site_name,
    CASE 
      WHEN CAST(fr.base_score + fr.multi_factor_bonus AS INT) > 100 THEN 100
      ELSE CAST(fr.base_score + fr.multi_factor_bonus AS INT)
    END AS risk_score,
    CASE
      WHEN fr.base_score + fr.multi_factor_bonus >= @risk_threshold_high THEN N'Critical Risk'
      WHEN fr.base_score + fr.multi_factor_bonus >= @risk_threshold_medium THEN N'High Risk'
      WHEN fr.base_score + fr.multi_factor_bonus >= @risk_threshold_low THEN N'Medium Risk'
      ELSE N'Low Risk'
    END AS risk_type,
    CONCAT(
      N'Hours: ', CAST(CAST(fr.hours_risk_score * fr.hours_multiplier AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Arrival: ', CAST(CAST(fr.arrival_risk_score * fr.arrival_multiplier AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Departure: ', CAST(CAST(fr.departure_risk_score * fr.departure_multiplier AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Non-workday: ', CAST(CAST(fr.non_workday_risk_score * fr.non_workday_multiplier AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Sustained presence: ', CAST(CAST(fr.sustained_presence_score AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Working while sick: ', CAST(CAST(fr.working_while_sick_score AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts; ',
      N'Multi-factor bonus: ', CAST(CAST(fr.multi_factor_bonus AS DECIMAL(5,1)) AS NVARCHAR(10)), N'pts'
    ) AS score_explanation,
    SYSUTCDATETIME() AS computed_at
  FROM #final_risk fr
  LEFT JOIN dbo.v_client_emp_department vd ON vd.client_id = fr.client_id AND vd.emp_id = fr.emp_id
  LEFT JOIN dbo.v_client_emp_role vr ON vr.client_id = fr.client_id AND vr.emp_id = fr.emp_id
  LEFT JOIN dbo.v_client_emp_site vs ON vs.client_id = fr.client_id AND vs.emp_id = fr.emp_id;
  
  -- ========================================================================
  -- VALIDATION
  -- ========================================================================
  
  IF @@ROWCOUNT = 0
  BEGIN
    RAISERROR('usp_calc_burnout_risk_score: No rows inserted into report_workload for client_id=%s. Check minimum data requirements.', 10, 1, @client_id);
  END
  
END
GO

