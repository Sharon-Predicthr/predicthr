  /* seed risk_interventions (dynamic, lookups by short_text) */
  DECLARE @add NVARCHAR(MAX) = N'
    DECLARE @iid INT;
    SELECT @iid = intervention_id FROM dbo.interventions WHERE short_text = @name AND is_active = 1;
    IF @iid IS NOT NULL
      INSERT INTO dbo.risk_interventions(risk_type, min_score, max_score, intervention_id, priority, is_active)
      VALUES (@rtype, @min, @max, @iid, @prio, 1);
  ';
  DECLARE @rtype NVARCHAR(40), @min INT, @max INT, @name NVARCHAR(200), @prio INT;

  /* FLIGHT */
  SET @rtype=N'flight';
  SELECT @min=0,  @max=39, @name=N'1:1 Manager Check-in',   @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=0,  @max=39, @name=N'Wellbeing Resources',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=40, @max=59, @name=N'Career Path Discussion',  @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Recognition Boost',       @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Role/Project Realignment',@prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=60, @max=79, @name=N'Career Path Discussion',  @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Compensation Review',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Flexible Work Arrangement',@prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Team Capacity Review',    @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=80, @max=100, @name=N'Career Path Discussion', @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Compensation Review',    @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Flexible Work Arrangement',@prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Escalation to HRBP',     @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  /* WORKLOAD */
  SET @rtype=N'workload';
  SELECT @min=0,  @max=39, @name=N'1:1 Manager Check-in',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=0,  @max=39, @name=N'Wellbeing Resources',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=40, @max=59, @name=N'Workload Rebalancing',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Wellbeing Resources',     @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Team Capacity Review',    @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=60, @max=79, @name=N'Workload Rebalancing',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Performance Check-in',    @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Coaching & Mentoring',    @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Skills Training',         @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=80, @max=100, @name=N'Workload Rebalancing',   @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Performance Check-in',   @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'HRBP Partnership',       @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=80, @max=100, @name=N'Escalation to HRBP',     @prio=4; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  /* INTEGRITY */
  SET @rtype=N'integrity';
  SELECT @min=0,  @max=39, @name=N'1:1 Manager Check-in',    @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=0,  @max=39, @name=N'Policy Refresher',        @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=40, @max=59, @name=N'Policy Refresher',        @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=40, @max=59, @name=N'Pattern Escalation',      @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  SELECT @min=60, @max=79, @name=N'Policy Refresher',        @prio=1; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Compliance Review',       @prio=2; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;
  SELECT @min=60, @max=79, @name=N'Badge/Access Audit',      @prio=3; EXEC sys.sp_executesql @add, N'@name nvarchar(200),@rtype nvarchar(40),@min int,@max int,@prio int', @name,@rtype,@min,@max,@prio;

  GO