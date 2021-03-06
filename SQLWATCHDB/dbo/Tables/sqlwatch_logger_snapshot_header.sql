﻿CREATE TABLE [dbo].[sqlwatch_logger_snapshot_header]
(
	[snapshot_time] datetime2(0),
	[snapshot_type_id] tinyint not null default 1 foreign key references dbo.[sqlwatch_config_snapshot_type]([snapshot_type_id]),
	[sql_instance] varchar(32) not null default @@SERVERNAME,
	[report_time] as convert(smalldatetime,DATEADD(MINUTE, CEILING(DATEDIFF(SECOND, 0, CAST(CAST([snapshot_time] AS DATETIME) AS TIME)) / 60.0), DATEDIFF(DAY, 0, [snapshot_time]))) persisted not null
	 CONSTRAINT pk_snapshot PRIMARY KEY clustered (
		[snapshot_time], [sql_instance], [snapshot_type_id]
	)
	--, constraint fk_snapshot_header_sql_instance foreign key (sql_instance) references dbo.sqlwatch_config_sql_instance (sql_instance) on delete cascade on update cascade
)
go
create nonclustered index idx_sqlwatch_logger_snapshot_header_report_time on [dbo].[sqlwatch_logger_snapshot_header] ([report_time])
--create nonclustered index idx_snapshot_type_id on [dbo].[sqlwatch_logger_snapshot_header]([snapshot_type_id])
go

--CREATE NONCLUSTERED INDEX idx_sqlwatch_snapshot_header_001
--ON [dbo].[sqlwatch_logger_snapshot_header] ([sql_instance])
--INCLUDE ([snapshot_time],[snapshot_type_id])
