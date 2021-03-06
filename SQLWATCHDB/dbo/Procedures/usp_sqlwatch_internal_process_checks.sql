﻿CREATE PROCEDURE [dbo].[usp_sqlwatch_internal_process_checks] 
AS
/*
-------------------------------------------------------------------------------------------------------------------
 usp_sqlwatch_internal_process_alerts

 Change Log:
	1.0 2019-11-03 - Marcin Gminski
-------------------------------------------------------------------------------------------------------------------
*/
set nocount on;
set xact_abort on;

declare @header nvarchar(100),
		@description nvarchar(2048),
		@sql nvarchar(max),
		@success varchar(100),
		@warning varchar(100),
		@critical varchar(100),
		@sql_instance varchar(32),
		@rule_id smallint,
		@check_start_time datetime2(7),
		@check_exec_time_ms real

declare @check_status varchar(50),
		@check_output_value decimal(28,2),
		@last_check_status varchar(50),
		@previous_value decimal(28,2),
		@last_status_change datetime,
		@retrigger_time smallint,
		@last_trigger_time datetime,
		@trigger_date datetime,
		@send_recovery bit,
		@send_email bit = 1,
		@retrigger_on_every_change bit,
		@target_type varchar(50)

declare @email_subject nvarchar(255),
		@email_body nvarchar(4000),
		@target_attributes nvarchar(255),
		@recipients nvarchar(255),
		@msg_payload nvarchar(max)

declare @snapshot_type_id tinyint = 18,
		@snapshot_date datetime2(0) = getutcdate()

declare @mail_return_code int

declare @check_output as table (
	value decimal(28,2)
	)

insert into [dbo].[sqlwatch_logger_snapshot_header]
values (@snapshot_date, @snapshot_type_id, @@SERVERNAME)

insert into [dbo].[sqlwatch_meta_alert]([sql_instance],[check_id])
select s.[sql_instance], s.[check_id]
from [dbo].[sqlwatch_config_alert_check] s
left join [dbo].[sqlwatch_meta_alert] t
on s.sql_instance = t.sql_instance
and s.check_id = t.check_id
where t.check_id is null

declare cur_rules cursor for
select	  ac.[check_id]
		, ac.[check_name]
		, ac.[check_description]
		, ac.[check_query]
		, ac.[check_threshold_warning]
		, ac.[check_threshold_critical]
		, ac.[sql_instance]
		, isnull(last_check_status,'')
		, t.target_address
		, t.[target_attributes]
		, [last_check_value]
		, isnull([last_status_change_date],'1970-01-01')
		, [trigger_repeat_period_minutes]
		, isnull([last_trigger_date],'1970-01-01')
		, [trigger_recovery]
		, [trigger_every_fail]
		, ac.[trigger_enabled]
		, [target_type]
from [dbo].[sqlwatch_config_alert_check] ac

	left join dbo.sqlwatch_meta_alert ma
	on ac.sql_instance = ma.sql_instance
	and ac.check_id = ma.check_id

	left join [dbo].[sqlwatch_config_alert_target] t
		on t.target_id = ac.target_id
where [check_enabled] = 1
and datediff(minute,isnull([last_check_date],'1970-01-01'),getdate()) >= isnull([check_frequency_minutes],0)

open cur_rules   
  
fetch next from cur_rules 
into @rule_id, @header, @description , @sql, @warning, @critical, @sql_instance, @last_check_status, @recipients, @target_attributes, @previous_value, @last_status_change, @retrigger_time
	, @last_trigger_time, @send_recovery, @retrigger_on_every_change, @send_email, @target_type
  
while @@FETCH_STATUS = 0  
begin
	

	set @check_status = null
	set @check_output_value = null
	delete from @check_output

	-------------------------------------------------------------------------------------------------------------------
	-- execute check and log output in variable:
	-------------------------------------------------------------------------------------------------------------------
	set @check_start_time = SYSDATETIME()
	insert into @check_output ([value])
	exec sp_executesql @sql

	set @check_exec_time_ms = convert(real,datediff(MICROSECOND,@check_start_time,SYSDATETIME()) * 1000.0)

	select @check_output_value = [value] from @check_output

	-------------------------------------------------------------------------------------------------------------------
	-- set check status based on the output:
	-- there are 3 basic options: OK, WARNING and CRITICAL.
	-- the critical could be greater or lower, or just different than the success for example:
	--	1. we can have an alert to trigger if someone drops database. in that case the critical would be less than desired value
	--	2. we can have a trigger if someone creates new databsae in which case, the critical would be greater than desired value
	--	3. we can have a trigger that checks for a number of databases and any change is critical either greater or lower.
	-------------------------------------------------------------------------------------------------------------------
Print 'Check id: ' + convert(varchar(50),@rule_id)

if @critical is not null and @check_status is null
	begin
		if left(@critical,2) = '<=' 
			begin
				if @check_output_value <= convert(decimal(28,2),replace(@critical,'<=',''))
					set @check_status = 'CRITICAL'
			end
		else if left(@critical,2) = '>='
			begin
				if @check_output_value >= convert(decimal(28,2),replace(@critical,'>=','')) 
					set @check_status = 'CRITICAL'
			end
		else if left(@critical,2) = '<>'
			begin
				if @check_output_value <> convert(decimal(28,2),replace(@critical,'<>','')) 
					set @check_status = 'CRITICAL'
			end

		else if left(@critical,1) = '>'
			begin
				if @check_output_value > convert(decimal(28,2),replace(@critical,'>','')) 
					set @check_status = 'CRITICAL'
			end
		else if left(@critical,1) = '<'
			begin
				if @check_output_value < convert(decimal(28,2),replace(@critical,'<','')) 
					set @check_status = 'CRITICAL'
			end
		else if left(@critical,1) = '='
			begin
				if @check_output_value = convert(decimal(28,2),replace(@critical,'=','')) 
					set @check_status = 'CRITICAL'
			end
		else
			begin
				if @check_output_value = convert(decimal(28,2),@critical) 
					set @check_status = 'CRITICAL'
			end
	end

Print 'CRITICAL: ' + isnull(convert(varchar(100),@check_output_value),'NULL') + ' ' + @check_status

if @warning is not null and @check_status is null
	begin
		if left(@warning,2) = '<=' 
			begin
				if @check_output_value <= convert(decimal(28,2),replace(@warning,'<=',''))
					set @check_status = 'WARNING'
			end
		else if left(@warning,2) = '>='
			begin
				if @check_output_value >= convert(decimal(28,2),replace(@warning,'>=','')) 
					set @check_status = 'WARNING'
			end
		else if left(@warning,2) = '<>'
			begin
				if @check_output_value <> convert(decimal(28,2),replace(@warning,'<>','')) 
					set @check_status = 'WARNING'
			end

		else if left(@warning,1) = '>'
			begin
				if @check_output_value > convert(decimal(28,2),replace(@warning,'>','')) 
					set @check_status = 'WARNING'
			end
		else if left(@warning,1) = '<'
			begin
				if @check_output_value < convert(decimal(28,2),replace(@warning,'<','')) 
					set @check_status = 'WARNING'
			end
		else if left(@warning,1) = '='
			begin
				if @check_output_value = convert(decimal(28,2),replace(@warning,'=','')) 
					set @check_status = 'WARNING'
			end
		else
			begin
				if @check_output_value = convert(decimal(28,2),@warning) 
					set @check_status = 'WARNING'
			end
	end

Print 'WARNING: ' + isnull(convert(varchar(100),@check_output_value),'NULL') + ' ' + @check_status

--if @success is not null and @check_status is null
--	begin
--		if left(@success,2) = '<='
--			begin
--				if @check_output_value <= convert(decimal(28,2),replace(@success,'<=','')) 
--				set @check_status = 'OK'
--			end
--		else if left(@success,2) = '>='
--			begin
--				if @check_output_value >= convert(decimal(28,2),replace(@success,'>=','')) 
--				set @check_status = 'OK'
--			end
--		else if left(@success,2) = '<>'
--			begin
--				if @check_output_value <> convert(decimal(28,2),replace(@success,'<>','')) 
--				set @check_status = 'OK'
--			end

--		else if left(@success,1) = '>'
--			begin
--				if @check_output_value > convert(decimal(28,2),replace(@success,'>','')) 
--				set @check_status = 'OK'
--			end
--		else if left(@success,1) = '<'
--			begin
--				if @check_output_value < convert(decimal(28,2),replace(@success,'<','')) 
--				set @check_status = 'OK'
--			end

--		--finally, if we are comparing eequal values, if the check output is not exactly
--		--what we are expecting we must set it to CRITICAL
--		else if left(@success,1) = '='
--			begin
--				if @check_output_value = convert(decimal(28,2),replace(@success,'=','')) 
--					begin
--						set @check_status = 'OK'
--					end
--				else
--					begin
--						set @check_status = 'CRITICAL'
--					end
--			end
--		else
--			begin
--				if @check_output_value = convert(decimal(28,2),@success) 
--					begin
--						set @check_status = 'OK'
--					end
--				else
--					begin
--						set @check_status = 'CRITICAL'
--					end
--			end
--	end

Print 'OK: ' + isnull(convert(varchar(100),@check_output_value),'NULL') + ' ' + @check_status

--if @success is null and @check_status is still null after having evaluated all conditions we are assuming OK status
--it will likely mean that it is not critical, nor warning so must be ok
if @check_status is null and @success is null
 set @check_status = 'OK'

--if we are still getting NULL then is must be an exception:
if @check_status is null and @critical is null
 set @check_status = 'UNKNOWN'

	-------------------------------------------------------------------------------------------------------------------
	-- update meta with the latest values
	-------------------------------------------------------------------------------------------------------------------
	update	[dbo].[sqlwatch_meta_alert]
	set last_check_date = getdate(),
		last_check_value = @check_output_value,
		last_check_status = @check_status,
		last_status_change_date = case when @last_check_status <> @check_status then getdate() else last_status_change_date end
	where [check_id] = @rule_id
	and sql_instance = @@SERVERNAME

	-------------------------------------------------------------------------------------------------------------------
	-- log alert in logger table and move on to the next item
	-------------------------------------------------------------------------------------------------------------------
	insert into [dbo].[sqlwatch_logger_alert_check]
	values (@@SERVERNAME, @snapshot_date, @snapshot_type_id, @rule_id, @check_output_value, case when @check_status = 'OK' then 1 else 0 end, case when @mail_return_code = 0 then 1 else 0 end, @check_exec_time_ms)








	-------------------------------------------------------------------------------------------------------------------
	-- BUILD PAYLOAD
	-------------------------------------------------------------------------------------------------------------------
	if @send_email = 1
		begin
			-------------------------------------------------------------------------------------------------------------------
			-- now set the email subject and appropriate flags to indicate what is happening.
			-- optons are below:
			-------------------------------------------------------------------------------------------------------------------

			-------------------------------------------------------------------------------------------------------------------
			-- if previous status is NOT ok and current status is OK the check has recovered from fail to success.
			-- we can send an email notyfing DBAs that the problem has gone away
			-------------------------------------------------------------------------------------------------------------------
			if @last_check_status <> 'OK' and @check_status = 'OK'
				begin
					set @send_email = @send_recovery
					set @email_subject = 'RECOVERED (OK): ' + @header + ' on ' + @sql_instance 
				end

			-------------------------------------------------------------------------------------------------------------------
			-- retrigger if the value has changed, regardless of the status.
			-- this is handy if we want to monitor every change after it has failed. for example we can set to monitor
			-- if number of logins is greater than 5 so if someone creates a new login we will get an email and then every time
			-- new login is created
			-------------------------------------------------------------------------------------------------------------------
			else if @check_status <> 'OK' and @retrigger_on_every_change = 1 and @check_output_value <> @previous_value
				begin
					set @email_subject = @header + ': ' + @check_status + ' on ' + @sql_instance
				end

			-------------------------------------------------------------------------------------------------------------------
			-- when the current status is not OK and the previous status has changed, it is a new notification:
			-------------------------------------------------------------------------------------------------------------------
			else if @check_status <> 'OK' and isnull(@last_check_status,'') <> @check_status
				begin
					set @email_subject = @header + ': ' + @check_status + ' on ' + @sql_instance
				end

			-------------------------------------------------------------------------------------------------------------------
			-- if the previous status is the same as the current status we would not normally send another email
			-- however, we can do if we set retrigger time. for example, we can be sending repeated alerts every hour so 
			-- they do not get forgotten about. 
			-------------------------------------------------------------------------------------------------------------------
			else if @check_status <> 'OK' and @last_check_status = @check_status and (@retrigger_time is not null and datediff(minute,@last_trigger_time,getdate()) > @retrigger_time)
				begin
					set @email_subject = 'REPEATED : ' + @check_status + ' ' + @header + ' on ' + @sql_instance 
				end

			-------------------------------------------------------------------------------------------------------------------
			-- finally, if the previous status is the same as current status and no retrigger defined we are not doing anything.
			-------------------------------------------------------------------------------------------------------------------
			else if @last_check_status = @check_status and (@retrigger_time is null or datediff(minute,@last_trigger_time,getdate()) < @retrigger_time)
				begin
					print 'Check id: ' + convert(varchar(10),@rule_id) + ': no action'
					goto ProcessNextCheck
				end
			else
				begin
					print 'Check id: ' + convert(varchar(10),@rule_id) + ': UNDEFINED'
					goto ProcessNextCheck
				end

			-------------------------------------------------------------------------------------------------------------------
			-- set email content
			-------------------------------------------------------------------------------------------------------------------
			set @email_body = '
Check: ' + @header + ' (CheckId:' + convert(varchar(50),@rule_id) + ')

Current status: ' + @check_status + '
Current value: ' + convert(varchar(100),@check_output_value) + '

Previous value: ' + convert(varchar(100),@previous_value) + '
Previous status: ' + @last_check_status + '
Previous change: ' + convert(varchar(23),@last_status_change,121) + '

SQL instance: ' + @sql_instance + '
Alert time: ' + convert(varchar(23),getdate(),121) + '

Warning threshold: ' + isnull(convert(varchar(100),@warning),'NULL') + '
Critical threshold: ' + isnull(convert(varchar(100),@critical),'NULL') + '
Retrigger time: ' + convert(varchar(50),case 
	when @retrigger_time is null then 'With every check'
	when @retrigger_time = 1 then 'Every 1 minute'
	when @retrigger_time > 1 then 'Every ' + convert(varchar(10),@retrigger_time) + ' minutes'
	else '' end) + '
Trigger rule: ' + case when @retrigger_on_every_change = 1 then 'On every value change' else ' Trigger once per status change' end + '
	
--- Check Description:

' + @description + '

--- Check Query:

' + @sql + '

---


Email sent from SQLWATCH on host: ' + @@SERVERNAME +'
https://docs.sqlwatch.io '


			update	[dbo].[sqlwatch_meta_alert]
			set last_trigger_date = getdate()
			where [check_id] = @rule_id


			if @target_type = 'sp_send_dbmail' and @email_subject is not null and @email_body is not null and @recipients is not null
				begin
					set @msg_payload = 'declare @rtn int
exec @rtn = msdb.dbo.sp_send_dbmail @recipients = ''' + @recipients + ''',
@subject = ''' + @email_subject + ''',
@body = ''' + replace(@email_body,'''','''''') + ''',
' + @target_attributes + '
select error=@rtn'

					-------------------------------------------------------------------------------------------------------------------
					-- insert into message queue table:
					-------------------------------------------------------------------------------------------------------------------
					insert into [dbo].[sqlwatch_meta_alert_notify_queue]([sql_instance], [notify_timestamp], [check_id], [target_type], [message_payload], [send_status])
					values (@@SERVERNAME, sysdatetime(), @rule_id, @target_type, @msg_payload, 0)
				end


			if upper(@target_type) = upper('PUSHOVER') and @email_subject is not null and @email_body is not null and @recipients is not null
				begin
					set @msg_payload = '$uri = "' + @recipients + '"
$parameters = @{
 ' + @target_attributes + '
  message = "' + @email_subject + '
 ' + replace(@email_body,'''','''''') + '"}
  
  $parameters | Invoke-RestMethod -Uri $uri -Method Post'

					-------------------------------------------------------------------------------------------------------------------
					-- insert into message queue table:
					-------------------------------------------------------------------------------------------------------------------
					insert into [dbo].[sqlwatch_meta_alert_notify_queue]([sql_instance], [notify_timestamp], [check_id], [target_type], [message_payload], [send_status])
					values (@@SERVERNAME, sysdatetime(), @rule_id, @target_type, @msg_payload, 0)
				end


			if upper(@target_type) = upper('Send-MailMessage') and @email_subject is not null and @email_body is not null and @recipients is not null
				begin
					set @msg_payload = '
$parameters = @{
To = "' + @recipients + '"
Subject = "' + @email_subject + '"
Body = "' + @email_body + '"
 ' + @target_attributes + '
 }
Send-MailMessage @parameters'

  					-------------------------------------------------------------------------------------------------------------------
					-- insert into message queue table:
					-------------------------------------------------------------------------------------------------------------------
					insert into [dbo].[sqlwatch_meta_alert_notify_queue]([sql_instance], [notify_timestamp], [check_id], [target_type], [message_payload], [send_status])
					values (@@SERVERNAME, sysdatetime(), @rule_id, @target_type, @msg_payload, 0)

				end
		end


	ProcessNextCheck:


	fetch next from cur_rules 
	into @rule_id, @header, @description , @sql, @warning, @critical, @sql_instance, @last_check_status, @recipients, @target_attributes, @previous_value, @last_status_change, @retrigger_time
		, @last_trigger_time, @send_recovery, @retrigger_on_every_change, @send_email, @target_type
	
end

close cur_rules
deallocate cur_rules