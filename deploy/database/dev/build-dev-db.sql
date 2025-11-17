-- build-dev-db.sql
-- Rebuilds full DB for DEV

USE master;
GO

IF DB_ID('PredictHR_DB_DEV') IS NOT NULL
BEGIN
    ALTER DATABASE PredictHR_DB_DEV SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE PredictHR_DB_DEV;
END;
GO

CREATE DATABASE PredictHR_DB_DEV;
GO

USE PredictHR_DB_DEV;
GO

:r ../migration_history.sql
GO

:r ../migrations/0001_init_schema.sql
:r ../migrations/0002_seed_default_users.sql
:r ../migrations/0003_create_fn_get_user_orders.sql
:r ../migrations/0004_create_vw_user_summary.sql
:r ../migrations/0005_create_sp_update_order_stats.sql
:r ../migrations/0006_alter_users_add_phone.sql
:r ../migrations/0007_alter_orders_add_status.sql
:r ../migrations/0008_update_vw_user_summary.sql
GO

