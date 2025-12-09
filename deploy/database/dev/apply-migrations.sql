DECLARE @path NVARCHAR(200) = '..\\migrations';
DECLARE @cmd NVARCHAR(MAX);


PRINT 'Executing migrations in order...';


EXEC xp_cmdshell 'dir /b /on ..\\migrations', NO_OUTPUT;


-- Your pipeline will execute each file automatically using sqlcmd
