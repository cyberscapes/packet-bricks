-- /usr/bin/lua
---------------------- STARTUP SCRIPT ---------------------------------





-----------------------------------------------------------------------
-- MACROS-&-UTILITY-FUNCS
-----------------------------------------------------------------------
STATS_PRINT_CYCLE_DEFAULT = 2
SLEEP_TIMEOUT = 1
PKT_BATCH=1024
NETMAP_LIN_PARAMS_PATH="/sys/module/netmap_lin/parameters/"
NETMAP_PIPES=64
NO_CPU_AFF=-1
NO_QIDS=-1

--see if the directory exists

local function directory_exists(sPath)
      if type(sPath) ~= "string" then return false end

      local response = os.execute( "cd " .. sPath )
      if response == 0 then
      	 return true
      end
      return false
end



--sleep function __self-explanatory__

local clock = os.clock
function sleep(n)  -- seconds
	 local t0 = clock()
	 while clock() - t0 <= n do end
end



-- A neat function that reads shell output given a shell command `c'
function shell(c)
	 local o, h
	 h = assert(io.popen(c,"r"))
	 o = h:read("*all")
	 h:close()
	 return o
end


-- check if netmap module is loaded in the system

function netmap_loaded()
	 if string.find((tostring(shell('uname'))), 'Linux') ~= nil then
	    if directory_exists(NETMAP_LIN_PARAMS_PATH) then
	       return true
	    end
	 end
	 if string.find((tostring(shell('uname'), 'FreeBSD'))) ~= nil then
	    if (tostring(shell('sysctl -a --pattern netmap'))) ~= nil then
	       return true
	    end
	 end
	 return false
end


-- enable netmap pipes framework

function enable_nmpipes()
	if string.find((tostring(shell('uname'))), 'Linux') ~= nil then
	 	 shell("echo " .. tostring(NETMAP_PIPES) .. " > " .. NETMAP_LIN_PARAMS_PATH .. "default_pipes")
	end
	if string.find((tostring(shell('uname'))), 'FreeBSD') ~= nil then
	   	 shell("sysctl -w dev.netmap.default_pipes=\"" .. tostring(NETMAP_PIPES) .. "\"")
	end	
end




-- check if you are root
-- XXX This needs to be improved
local function check_superuser()
      if string.find((tostring(shell('whoami'))), 'root') == nil then 
      	 return false
      end
      return true
end

-----------------------------------------------------------------------









-----------------------------------------------------------------------
-- S I N G L E - T H R E A D E D - S E T U P
-----------------------------------------------------------------------
--init function  __initializes pkteng thread and links it with a__
--		 __netmap-enabled interface. collects PKT_BATCH__
--		 __pkts at a time. "cpu" and "batch" params can remain__
--		 __unspecified by passing '-1'. Next creates 4 netmap__
--		 __pipe channels to forward packets to userland apps__

function init()
	 -- check if netmap module is loaded
	 if netmap_loaded() == false then
	    print 'Netmap module does not exist'
	    os.exit(-1)
	 end

	 -- check if you are root
	 if check_superuser() == false then
	    print 'You have to be superuser to run this function'
	    os.exit(-1)
	 end

	 -- create a global variable pe
	 local pe = PktEngine.new("e0", "netmap", NO_CPU_AFF)

	 -- create ingress interface
	 local intf_in = Interface.new("eth3")

	 -- now link it!
	 pe:link(intf_in, PKT_BATCH, NO_QIDS)


	 -- egress interfaces
	 local intf0 = Interface.new("eth3{0")
	 local intf1 = Interface.new("eth3{1")
	 --local intf2 = Interface.new("eth3{2")
	 --local intf3 = Interface.new("eth3{3")
	 local intf_out = Interface.new("eth2")


	 -- enable underlying netmap pipe framework
	 enable_nmpipes()


	 -- Use this line to load balance traffic across interfaces
	 intf_in:connect_loadbal(pe, intf0, intf1, intf_out)
	 
	 -- Use this line to split traffic across interfaces (incl. egress iface)
	 --intf_in:connect_loadbal(pe, intf0, intf1, intf2, intf3, intf_out)

         
	 --lb0 = LoadBalance.new("2-tuple")
         --brolb0 = LoadBalance.new("2-tuple")
	 --lb0:connect_input(intf_in) 
         --lb0:connect_output(intf0, intf1)

         --dup0 = Duplicator.new()
         --dup0:connect_input(intf_in)
         --dup0:connect_output(brolb0)
         --dup0:connect_output(snortlb0)
         --dup0:connect_output(tcpdump_if)


         -- i0 <-> dup0 <-> filter0(name="blocker") <-> i1
         --         |
         --       filter1(name="shunter")
         --         |
         --        lb0 -> bro, snort, etc 

         --pe.add(lb0)
         --pe.add(dup0)


         --lb0:balance_as("4-tuple")

	 --intf_in:connect_loadbal(pe, intf0, intf1)
	 --intf0:connect_loadbal(pe, intf2, intf3)

	 -- Use this line to duplicate traffic across interfaces
	 --intf_in:connect_dup(pe, intf0, intf1, intf2, intf3)
	 --intf_in:connect_dup(pe, intf0, intf1, intf2, intf3, intf_out)

	 -- Use this line to forward packets to a different Ethernet port
	 --intf_in:connect_loadbal(pe, intf_out)
end
-----------------------------------------------------------------------
--start function  __starts pkteng and prints overall per sec__
--		  __stats for STATS_PRINT_CYCLE_DEFAULT secs__

function start()
	 -- start reading pkts from the interface
	 local pe = PktEngine.retrieve("e0")
	 pe:start()

	 local i = 0
	 repeat
	     sleep(SLEEP_TIMEOUT)
	     --pe:show_stats()
	     PACF.show_stats()
	     i = i + 1
	 until i > STATS_PRINT_CYCLE_DEFAULT
end
-----------------------------------------------------------------------
--stop function  __stops the pkteng before printing the final stats.__
--		 __it then unlinks the interface from the engine and__
--		 __finally frees the engine context from the system__
function stop()
	 local pe = PktEngine.retrieve("e0")
	 --pe:show_stats()
	 PACF.show_stats()

	 pe:stop()
	 sleep(SLEEP_TIMEOUT)

	 pe:unlink()
	 sleep(SLEEP_TIMEOUT)

	 pe:delete()
	 --PACF.shutdown()
end
-----------------------------------------------------------------------





-----------------------------------------------------------------------
-- 4 - T H R E A D S - S E T U P
-----------------------------------------------------------------------
--init4 function __initializes 4 pkteng threads and links it with a__
--		 __netmap-enabled interface. collects PKT_BATCH    __
--		 __pkts at a time. "cpu", "batch" & "qid" params   __
--		 __can remain unspecified by passing '-1'	   __
--		 __						   __
--		 ++_____________HOW TO USE H.W QUEUES______________++
--		 ++Please make sure that the driver is initialized ++
--		 ++with the right no. of h/w queues. In this setup,++
--		 ++ cpu_thread=0 is registered with H/W queue 0    ++
--		 ++ cpu_thread=1 is registered with H/W queue 1	   ++
--		 ++ cpu_thread=2 is registered with H/W queue 2	   ++
--		 ++ cpu_thread=3 is registered with H/W queue 3	   ++
--		 ++________________________________________________++

function init4()
	 -- check if netmap module is loaded
	 if netmap_loaded() == false then
	    print 'Netmap module does not exist'
	    os.exit(-1)
	 end

	 -- check if you are root
	 if check_superuser() == false then
	    print 'You have to be superuser to run this function'
	    os.exit(-1)
	 end

	 -- enable underlying netmap pipe framework
	 enable_nmpipes()

	 -- create a global variable of table type to create 4 engines
	 local pes = {}
	 -- create a global ingress interface variable
	 local intf_in = Interface.new("eth3")

	 -- egress interfaces
	 local intf_out = Interface.new("eth2")


	 -- enable underlying netmap pipe framework
	 enable_nmpipes()

	 for cnt = 0, 3 do
	 	 pes["pe" .. cnt] = PktEngine.new("e" .. cnt, "netmap", cnt)
	 	 pes["pe" .. cnt]:link(intf_in, PKT_BATCH, cnt)
		 
		 local intf = Interface.new("eth3{" .. cnt)
		 -- Use this line to load balance traffic across interfaces
	 	 intf_in:connect_loadbal(pes["pe" .. cnt], intf)

	 	 -- Use this line to duplicate traffic across interfaces
	 	 --intf_in:connect_dup(pes["pe" .. cnt], intf)

	 	 -- Use this line to forward packets to a different Ethernet port
	 	 --intf_in:connect_loadbal(pes["pe" .. cnt], intf_out)
	 end
end
-----------------------------------------------------------------------
--start4 function __starts all 4 pktengs and prints overall per sec__
--		  __stats for STATS_PRINT_CYCLE_DEFAULT secs__

function start4()
	 for cnt = 0, 3 do
	     	 local pe = PktEngine.retrieve("e" .. cnt)
	 	 pe:start()
	 end

	 local i = 0
	 repeat
	     sleep(SLEEP_TIMEOUT)
	     PACF.show_stats()
	     i = i + 1
	 until i > STATS_PRINT_CYCLE_DEFAULT
end
-----------------------------------------------------------------------
--stop4 function __stops the pktengs before printing the final stats.__
--		 __it then unlinks the interface from the engine and__
--		 __finally frees the engine context from the system__
function stop4()
	 PACF.show_stats()
	 for cnt = 0, 3 do
	     	 local pe = PktEngine.retrieve("e" .. cnt)
		 pe:stop()
	 end

	 sleep(SLEEP_TIMEOUT)

	 for cnt = 0, 3 do
	     	 local pe = PktEngine.retrieve("e" .. cnt)
	 	 pe:unlink()
	 end

	 sleep(SLEEP_TIMEOUT)

	 for cnt = 0, 3 do
	     	 local pe = PktEngine.retrieve("e" .. cnt)
	 	 pe:delete()
	 end

	 --PACF.shutdown()
end
-----------------------------------------------------------------------





-----------------------------------------------------------------------
-- S T A R T _ OF _  S C R I P T
-----------------------------------------------------------------------
-- __"main" function (Commented for user's convenience)__
--
-------- __This command prints out the main help menu__
-- PACF.help()
-------- __This command shows the current status of PACF__
-- PACF.print_status()
-------- __This prints out the __pkt_engine__ help menu__
-- PktEngine.help()
-------- __Initialize the system__
-- init()
-------- __Start the engine__
-- start()
-------- __Stop the engine__
-- stop()
-------- __The following commands quits the session__
-- PACF.shutdown()
-----------------------------------------------------------------------