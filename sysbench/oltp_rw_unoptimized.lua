#!/usr/bin/env sysbench

-- replace oltp_common.lua
-- cp oltp_common.lua /usr/share/sysbench/oltp_common.lua


-- usage
-- oltp_rw_unoptimized.lua \
--	--mysql-host=192.168.56.40 \
--	--mysql-password=sbtest \
--	--mysql-user=sbtest \
--	--mysql-port=3306 \
--	--table-size=1000000 \
--	--tables=1 \
--	--threads=8 \
--	--time=0 \
--	--report-interval=1 \
--	--read_freq=0.84 \
--	--delete_freq=0.06 \
--	--update_freq=0.1 \
--	--thresholds=100,500 \
--	run
--
-- example for write heavy pg workload connected to pgbouncer with pool_mode=transaction
--	./oltp_rw_unoptimized.lua \
--	--db-driver=pgsql --pgsql-host=127.0.0.1 --pgsql-port=6434 --pgsql-user=sbtest --pgsql-password=sbtest \
--	--threads=350 --tables=5 --table-size=100000 --group-trx=on --time=100 --report-interval=1 \
--	--distinct_ranges=2 --order_ranges=2 --point_selects=1 --read-prct=0.9 --fullscan_freq=0 --join_fullscan_freq=0 --double_fullscan_freq=0.00001 \
--	--delete_freq=0.1 --update_freq=0 \
--	--sleep_freq=0.01 --sleep_between_events_freq=0.2 --sleep-time-max=2 \
--	--lazy_thread_init  --pgbouncer-tx-mode \
--	run


require('.oltp_common')

sysbench.cmdline.options.read_freq					= {"Frequency of reads", 0.95}
sysbench.cmdline.options.update_freq				= {"Frequency of updates", 0.025}
sysbench.cmdline.options.delete_freq				= {"Frequency of deletes and inserts", 0.025}
sysbench.cmdline.options.group_trx					= {"Group every actions that triggered in a single transaction for each event per thread. Keeping it false will only group necessary actions together (deletes and inserts). Disables --skip_trx.", false}

sysbench.cmdline.options.insert_large_text_freq		= {"Frequency of large text insertion among inserts. Requires delete_freq to be non-zero", 0}
sysbench.cmdline.options.large_text_size_min		= {"Minimum size of large texts (Kibibytes)", 512}
sysbench.cmdline.options.large_text_size_max		= {"Maximum size of large texts (Kibibytes)", 2048}

sysbench.cmdline.options.fullscan_freq				= {"Frequency of table full scan among selects", 0}
sysbench.cmdline.options.join_fullscan_freq			= {"Frequency of joins not using indexes among selects (if tables >= 2)", 0}
sysbench.cmdline.options.double_fullscan_freq		= {"Frequency of joins not using indexes along with a base table full scan among selects (if tables >= 2). Should be set very low (0.00001)", 0}
sysbench.cmdline.options.fulltext					= {"Add fulltexts indexes on large_text columns (only on mysql)", false}

sysbench.cmdline.options.sleep_freq					= {"Frequency of sleeps within tx", 0}
sysbench.cmdline.options.sleep_between_events_freq	= {"Frequency of sleeps between 2 events", 0}
sysbench.cmdline.options.sleep_time_max				= {"Maximum time of sleeps in seconds", 10}

sysbench.cmdline.options.reconnect_freq				= {"Chance of disconnecting and reconnecting threads after an event", 0}
sysbench.cmdline.options.lazy_thread_init			= {"Init thread only when executing event, disconnect after. Useful with pgbouncer transaction pool_mode", false}
sysbench.cmdline.options.pgbouncer_tx_mode			= {"Prepare stmt after opening a tx for pgbouncer pool_mode=transaction. Requires --group_trx as well", false}

sysbench.cmdline.options.verbose_display			= {"Enable report hook to display percents of DMLs and DQLs and remove some infos", true}
sysbench.cmdline.options.disable_color				= {"Disable colors for verbose display", false}
sysbench.cmdline.options.csv_output					= {"Display final report in csv format(FORCED TO TRUE)\n Format: time_total,threads,tables,table_size,reads,writes,other,latency_min,latency_max,latency_avg,errors", false}
sysbench.cmdline.options.thresholds					= {"Disable colors for verbose display", "1000,2000"}


-- this part requires the forked oltp_common
-- stmt_defs is defined with "local", removing the "local" flag enable to add stmt and benefits from every helpers out of the box
stmt_defs.fullscans = {
	"SELECT c FROM sbtest%u WHERE pad=? LIMIT 30",
	{t.CHAR, 60} 
}

-- not full scan on pg, but provoke an index scan
stmt_defs.join_fullscans = {
	"SELECT sb1.id FROM sbtest%u as sb1 JOIN sbtest1 as sb2 ON sb1.id = (sb2.id+3) where sb1.id = ?",
	t.INT 
}

-- works as well on pg
stmt_defs.double_fullscans = {
	"SELECT sb1.id FROM sbtest%u as sb1 JOIN sbtest2 as sb2 ON (sb1.id-3) = (sb2.id+3) ORDER BY sb2.id LIMIT 2000",
}

stmt_defs.insert_large_text_mysql = {
	"INSERT INTO sbtest%u (id, k, c, pad, large_text) VALUES (?, ?, ?, ?, repeat('x', ?))",
	t.INT, t.INT, {t.CHAR, 120}, {t.CHAR, 60}, t.INT
}

stmt_defs.insert_large_text_pgsql = {
	"INSERT INTO sbtest%u (id, k, c, pad, large_text) VALUES (?, ?, ?, ?, repeat('x', ?::int))",
	t.INT, t.INT, {t.CHAR, 120}, {t.CHAR, 60}, t.INT
}

stmt_defs.sleeps_mysql = {
	"select sleep(?)",
	t.INT 
}

stmt_defs.sleeps_pgsql = {
	"select pg_sleep(?)",
	t.INT 
}

function append_driver()
	if sysbench.opt.db_driver == "pgsql" then 
		return "_pgsql" 
	else
		return "_mysql" 
	end
end

function execute_fullscans()
	local tnum = get_table_num()

	param[tnum].fullscans[1]:set_rand_str("%###")

	stmt[tnum].fullscans:execute()
end

function execute_join_fullscans()
	local tnum = get_table_num()

	param[tnum].join_fullscans[1]:set(get_id())

	stmt[tnum].join_fullscans:execute()
end

function execute_double_fullscans()
	local tnum = get_table_num()

	stmt[tnum].double_fullscans:execute()
end

function execute_delete_insert_large_text()
	local tnum = get_table_num()
	local id = get_id()
	local k = get_id()
	param[tnum].deletes[1]:set(id)

	local query = "insert_large_text"..append_driver()

	param[tnum][query][1]:set(id)
	param[tnum][query][2]:set(k)
	param[tnum][query][3]:set("##")
	param[tnum][query][4]:set("##")
	param[tnum][query][5]:set(sysbench.rand.uniform(sysbench.opt.large_text_size_min*1024, sysbench.opt.large_text_size_max*1024))

	stmt[tnum].deletes:execute()
	stmt[tnum][query]:execute()
end

function execute_sleeps()
	local tnum = get_table_num()
	local query = "sleeps"..append_driver()

	param[tnum][query][1]:set(sysbench.rand.uniform(1, sysbench.opt.sleep_time_max))
	stmt[tnum][query]:execute()
end

function disconnect_reconnect()
	thread_done()
	thread_init()
end


function prepare()
	cmd_prepare()
	local con=sysbench.sql.driver():connect()


	for  i = sysbench.tid % sysbench.opt.threads + 1, sysbench.opt.tables, sysbench.opt.threads do
		if sysbench.opt.insert_large_text_freq > 0 then
			print("Adding large_text column on sbtest"..i)
			
			local type='LONGTEXT'
			if sysbench.opt.db_driver == "pgsql" then type='TEXT' end

			con:query("ALTER TABLE sbtest"..i.." ADD COLUMN large_text "..type)
			if sysbench.opt.db_driver == "mysql" and sysbench.opt.fulltext then
				con:query("ALTER TABLE sbtest"..i.." ADD FULLTEXT INDEX sbtest"..i.."_ft_idx(large_text)")
			end
		end
	end

end

sysbench.cmdline.commands = {
	prepare = {prepare, sysbench.cmdline.PARALLEL_COMMAND},
}

function thread_init()
	if sysbench.opt.lazy_thread_init then
		return
	end
	internal_thread_init()
end

-- copied from oltp_common thread_init()
-- needed to override thread_init for pgbouncer transaction mode
-- else, every connections expect to have a fully prepped postgres connection during init, which may not be possible
function internal_thread_init()
	drv = sysbench.sql.driver()
	con = drv:connect()

	-- Create global nested tables for prepared statements and their
	-- parameters. We need a statement and a parameter set for each combination
	-- of connection/table/query
	stmt = {}
	param = {}

	for t = 1, sysbench.opt.tables do
		stmt[t] = {}
		param[t] = {}
	end

	-- This function is a 'callback' defined by individual benchmark scripts
	prepare_statements()
end


-- max_freq_from a list of tests, with "freq" defined
-- See event(), it is used to stop event execution early if nothing will trigger
function max_freq_from(ts)
	mr = 0.0
	for _,v in pairs(ts) do
		if (mr < v.freq) then
			mr = v.freq
		end
	end
	return mr
end


-- add_individual_transaction add begin/commit for individual actions if we did not specify to group actions in a single transaction
-- It expects and returns an array
function add_individual_transaction(fs)
	if sysbench.opt.group_trx then return fs end
	arr = { begin }
	for _, f in pairs(fs) do arr[#arr+1] = f end
	arr[#arr+1] = commit;
	return arr
end

-- decides the read type depending on the random number generated
-- this prevents a "unlucky" random number from triggering every fullscans at once.
function reads(rand)
	-- most impacting query, so the least frequent one
	if rand < sysbench.opt.double_fullscan_freq then execute_double_fullscans(); return end

	-- 2nd most impacting query
	-- adding frequencies to avoid "overstepping" in case they have the same frequencies
	local freq_fullscans =  sysbench.opt.double_fullscan_freq + sysbench.opt.fullscan_freq
	if rand < freq_fullscans then execute_fullscans(); return end

	-- 3rd most impacting query, join full scans, it's "only" index scans 
	local freq_join_fullscans = freq_fullscans + sysbench.opt.join_fullscan_freq
        if rand < freq_join_fullscans then execute_join_fullscans(); return end

	-- regular sysbench selects
	execute_point_selects()
end

function inserts(rand)
	if rand < sysbench.opt.insert_large_text_freq then execute_delete_insert_large_text(); return end

	execute_delete_inserts()
end

-- prepare_statements must be defined for sysbench to work 
-- Every thread-global objects can be setup here
function prepare_statements()

	prepare_begin()
	prepare_commit()
	
	sysbench.opt.point_selects=1
	prepare_point_selects()
	prepare_index_updates()
	prepare_non_index_updates()
	prepare_delete_inserts()
	if sysbench.opt.fullscan_freq > 0 then
   		prepare_for_each_table("fullscans")
	end
	if sysbench.opt.join_fullscan_freq > 0 then
   		prepare_for_each_table("join_fullscans")
	end
	if sysbench.opt.double_fullscan_freq > 0 then
   		prepare_for_each_table("double_fullscans")
	end
	if sysbench.opt.insert_large_text_freq > 0 then
   		prepare_for_each_table("insert_large_text"..append_driver())
	end
	if sysbench.opt.sleep_freq > 0 then
   		prepare_for_each_table("sleeps"..append_driver())
	end

	if sysbench.opt.group_trx then sysbench.opt.skip_trx = false end


	-- variables are global if not explicitely local
	-- need_rand is whether the funcs expect having the random number selected for the event as input paramater
	tests = {
		{freq = sysbench.opt.read_freq, need_rand = true, funcs = {reads}},
		{freq = sysbench.opt.delete_freq/2, need_rand = true, funcs = {inserts}},
		{freq = sysbench.opt.update_freq/2, funcs = add_individual_transaction({execute_index_updates, execute_non_index_updates})},
		{freq = sysbench.opt.sleep_freq, funcs={execute_sleeps}},
	}
	max_freq = max_freq_from(tests)
		
end

-- event is the main function executed during benchmark
function event()
	if sysbench.opt.lazy_thread_init then
		internal_thread_init()
	end

	local rand = sysbench.rand.uniform(1, 10000000)/10000000

	-- If returned random is above every tests "freq", none of our tests will be triggered, future iterations are useless. 
	if max_freq < rand then
		return
	end

	
	if sysbench.opt.group_trx then 
		--begin() 
      		con:query("begin;")
		if sysbench.opt.pgbouncer_tx_mode then
			prepare_statements()
		end
	end
	for _, v in pairs(tests) do
		if (v.freq >= rand) then
			if v.need_rand then for _, f in pairs(v.funcs) do f(rand) end
			else for _, f in pairs(v.funcs) do f() end
			end
		end
	end
	if sysbench.opt.group_trx then commit() end

	if (sysbench.opt.sleep_between_events_freq >= rand) then
		-- lua as no sleep feature
		-- io.popen is better then os.exec because it will respect termination signals 
		-- does not block other thread. The call is synchronous
		local timer = io.popen("sleep " .. sysbench.rand.uniform(1, sysbench.opt.sleep_time_max))
    	timer:close()
	end

	if sysbench.opt.lazy_thread_init then
		thread_done()
		return
	end
	if sysbench.opt.reconnect_freq >= rand then
		disconnect_reconnect()
	end
end



sysbench.hooks.report_intermediate = 
	function (stat)
		if (not sysbench.opt.verbose_display) then
			return sysbench.report_default(stat)
		end

		local seconds = stat.time_interval
		-- This is derived from sysbench.report_default, formulas were copy-pasted 
		local total_reqs = (stat.reads + stat.writes + stat.other) / seconds
		local total_reads = stat.reads / seconds
		local total_writes = stat.writes / seconds
		local total_rw = total_reads + total_writes
		local total_others = stat.other / seconds
		local errs = stat.errors / seconds
		print(string.format(
			"[ %.0fs ] thds: %u | " .. 
			"qps: " .. get_threshold_color(total_reqs) .. "%4.2f" .. get_color("reset").. " | " ..
			"r: %4.2f(" .. get_color("blue") .."%4.2f %%" .. get_color("reset") .. ") | " .. 
			"w: %4.2f(" .. get_color("blue") .."%4.2f %%" .. get_color("reset") .. ") | " ..
			"o: %4.2f | " .. 
			"err/s: " .. alert_if_above_zero(errs) .. "%4.2f" .. get_color("reset"),
			stat.time_total,
			stat.threads_running,
			total_reqs,
			total_reads,
			total_reads / total_rw * 100,
			total_writes,
			total_writes / total_rw * 100,
			total_others,
			errs
		))
	end
--[[

sysbench.hooks.report_cumulative = function (stat) 
-- function final_report_csv(stat)
	
	-- One day
--[[	if not sysbench.opt.csv_output then 
		return sysbench.report_cumulative(stat)
	end
--]]
--[[--
	print(string.format(
		"%.0f,%u,%u,%u," ..
		"%4.2f,%4.2f,%4.2f," ..
		"%4.2f,%4.2f,%4.2f," ..
		"%4.2f,%4.2f,%4.2f," ..
		"%4.2f",
		stat.time_total, sysbench.opt.threads,
		sysbench.opt.tables, sysbench.opt.table_size,
		sysbench.opt.read_freq, sysbench.opt.update_freq, sysbench.opt.delete_freq,
		stat.reads, stat.writes, stat.other,
		stat.latency_min, stat.latency_max, stat.latency_avg,
		stat.errors
	))
end
--]]
		


-- We can find additional colors, http://lua-users.org/wiki/AnsiTerminalColors
local colors = {
	reset 	= 0,
	red 	= 31,
	green 	= 32,
	yellow 	= 33,
	blue 	= 34,
	magenta = 35,
	cyan 	= 36,
	white 	= 37,
}

function get_color(color)
	if (sysbench.opt.disable_color) then
		return ""
	end
	return "\27["..colors[color].."m"
end

local thresholds_colors = {
	"red",
	"yellow",
}

function alert_if_above_zero(v)
	if (v > 0) then return get_color("red") else return "" end
end


function get_threshold_color(v)
	local i = 1;
	-- split by commas
	for s in string.gmatch(sysbench.opt.thresholds, "([^,]+)") do
		if (v <= tonumber(s)) then
			return get_color(thresholds_colors[i])
		end
		i = i + 1
	end
	return get_color("reset")
end

