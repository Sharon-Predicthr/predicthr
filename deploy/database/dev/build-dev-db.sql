PRINT '=== Starting DEV database build ===';

PRINT 'Applying base objects...';

:r ../objects/tables/Employees.sql
:r ../objects/tables/Departments.sql

:r ../objects/views/vwEmployeesFull.sql

:r ../objects/procedures/uspUpsertEmployee.sql
:r ../objects/procedures/uspGetEmployeeById.sql
:r ../objects/procedures/uspGetAllEmployees.sql
:r ../objects/procedures/uspDeleteEmployee.sql

PRINT '=== Base DB created — migrations will run from shell ===';
GO
