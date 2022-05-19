#############################################################################
#!/bin/bash
#
# SCRIPTNAME: vecna.monitor_tomcat.sh 
#
# Creator: Dino Sims
# Email: dino.sims@vecna.com 
# Creation Date: 13 May 2022 
# Version: 1.0
#
# DESCRIPTION 
# script to automatically restart services to insure VetLink is opertional
# this is mainly a hack to fix bug in tomcat or our app 
# see https://issues.vecna.com/browse/POPS-14515 for details
# 
# ASSUMPTIONS 
# crond is installed and running
# Ncat (nc) network tool is installed
#
# NOTE
# Due to the fact that it takes over 3 mins for the app to come up to the
# point that you can access it with a browser or curl, We can't run a curl
# test more that once every 4 mins or so otherwise you could create a condition
# that restarts tomcat three times if you're checking every 1 min, before the
# app is up. So I've added an option that will allow us to create a separate
# crontab that runs say every 6 mins that checks for the app login page using
# curl. By doing this, the script will have 6 times if you running it every
# minute, to restart services so we don't get false positives or create an
# issue because we restart too quickly. 
# 
#############################################################################


#############################################################################
# Vars 
#############################################################################
SCRIPTNAME=vecna.monitor_tomcat.sh
TFTPBOOT_DIR='/tftpboot'
POSTGRESQL="postgresql-9.3"
#POSTGRESQL="postgresql-12"

# For debugging 
# touch /var/log/$SCRIPTNAME.log.debug

function logstart ()
{
    FILELOG=/var/log/$SCRIPTNAME.log
    exec 1>>$FILELOG
    exec 2>>$FILELOG
    echo "########################################################"
    echo "*** Vecna Monitor Tomcat START `date +"%b %e %R:%S" `***" 
    echo "server `hostname` user `whoami` starting $0 in `pwd`"
    echo; echo "Logged in:";w -h
    echo; echo "Disk status:";df -h 
    echo; echo "Process status:";ps auxfw
    echo
    echo "########################################################"
} 

function check_nc ()
{
   echo "$FUNCNAME: start"
   if [ `which nc | grep nc` ]
     then
       echo "nc found."
   else echo "ERROR:`date` You must install nc (as root, yum -y install nc)."
     echo "Aborting..."
     exit 1
   fi
   echo "$FUNCNAME: done"
}

function check_app_port ()
{
   echo "$FUNCNAME: start"
   ncoutput=$( nc 127.0.0.1 443 -vz -w10 2>&1 )
   printf "%s\n" "$ncoutput" > /tmp/ncoutput.out
   cat /tmp/ncoutput.out
   if [ "`grep Connected /tmp/ncoutput.out`" = "Ncat: Connected to 127.0.0.1:443." ]
     then
       echo "App is listening on port 443."
   else 
     echo "ERROR:`date` App NOT RUNNING. Ncat check FAILED."
     echo "Attempting to restart..."
     systemctl stop tomcat 
     pkill -9 -u tomcat tomcat
     systemctl restart $POSTGRESQL
     systemctl start tomcat
     #exit 1
   fi
   rm -f /tmp/ncoutput.out
   echo "$FUNCNAME: done"
}

function check_app_status ()
{
   echo "************************************* $FUNCNAME: start `date` ***************************************************"
   curloutput=$( curl --insecure https://`hostname`/vCas/login 2>&1 )
   printf "%s\n" "$curloutput" > /tmp/curloutput.out
   #cat /tmp/curloutput.out # for testing
   #if [ "`grep 'To access the VetLink Application please enter your Vista Access and Verify  Code.' /tmp/curloutput.out`" = "To access the VetLink Application please enter your Vista Access and Verify  Code." ]
   if [ "`grep 'To access the VetLink Application please enter your Vista Access and Verify  Code.' /tmp/curloutput.out`" ]
     then
       echo "App login page can be accessed via curl."
   else  
     echo "ERROR:`date` App login page can't be accessed via curl!"
     echo "Attempting to restart..."
     systemctl stop tomcat
     pkill -9 -u tomcat tomcat
     systemctl restart $POSTGRESQL 
     systemctl start tomcat
     #exit 1
   fi
   rm -f /tmp/curloutput.out
   echo "************************************* $FUNCNAME: done `date` ***************************************************"
}

function check_dns ()
{
        echo "$FUNCNAME: start"
        MYHOSTNAME=`hostname`
        NSLOOKUP=`dig $MYHOSTNAME | awk 'p{print $1}/^;; ANSWER SECTION:$/{p=1}/^$/{p=0}'`
        #NSLOOKUP=`nslookup $MYHOSTNAME | awk 'NR==5 {print $2}'` # does not work reliably
        if [ "$NSLOOKUP" = "$MYHOSTNAME." ]
           then
              echo "DNS is OK." 
        else   
           echo "DNS ERROR:`date` Can't find $MYHOSTNAME in DNS. Contact Vecna Support or DevOps, or VA OI&T"
           #echo "Aborting..."
           #exit 1
        fi
        echo "$FUNCNAME: done"
}

function check_root_user ()
{
   echo "$FUNCNAME: start"
   if [ `whoami | grep root` ]
   then
     echo "We are root." 
   else echo "ERROR:`date` You must be root to run."
     echo "Aborting..."
     exit 1
   fi
   echo "$FUNCNAME: done"
}

function check_postgres_status ()
{
 # postgresql-12
 # Active: active (running) since
 # Active: inactive (dead) since
 # postgresql-9.3
 # Active: active (exited) since
 # Active: inactive (dead) since
 echo "$FUNCNAME: start"
 case $POSTGRESQL in
   postgresql-9.3) 
     if [ "`systemctl status postgresql-9.3 | grep 'Active: active (exited) since'`" ]
       then
         echo "postgresql-9.3 is running."
     else
       echo "ERROR:`date` postgresql-9.3 not running."
       echo "Attempting to restart..."
       systemctl restart postgresql-9.3 
     fi;;
   postgresql-12)
     if [ "`systemctl status postgresql-12 | grep 'Active: active (running) since'`" ]
       then
         echo "postgresql-12 is running."
     else
       echo "ERROR:`date` postgresql-12 not running."
       echo "Attempting to restart..."
       systemctl restart postgresql-12 
     fi;;
   *) echo "ERROR:`date` Postgresql version can't be determined.";; 
 esac
 echo "$FUNCNAME: done"
}
	
function check_postgres_status_old ()
{
# Active: active (exited)
# Active: inactive (dead)
echo "$FUNCNAME: start"
      if [ "$POSTGRESQL" = "postgresql-9.3" ];then    
	if [ "`systemctl status postgresql-9.3 | grep Active | grep active | grep exited `" ]
	   then
	     echo "postgresql is running."
	else 
           echo "ERROR:`date` Postgresql not running."
	   echo "Attempting to restart..."
           systemctl restart $POSTGRESQL 
	   #exit 1
	fi
      fi 

      if [ "$POSTGRESQL" = "postgresql-12" ];then    
	if [ "`systemctl status postgresql-12 | grep Active | grep active | grep exited `" ]
	   then
	     echo "postgresql is running."
	else 
           echo "ERROR:`date` Postgresql not running."
	   echo "Attempting to restart..."
           systemctl restart $POSTGRESQL 
	   #exit 1
	fi
      fi 
echo "$FUNCNAME: done"
}

function check_postgres_port ()
{
   echo "$FUNCNAME: start"
   ncoutput=$( nc 127.0.0.1 5432 -vz -w10 2>&1 )
   printf "%s\n" "$ncoutput" > /tmp/ncoutput.out
   cat /tmp/ncoutput.out
   if [ "`grep Connected /tmp/ncoutput.out`" = "Ncat: Connected to 127.0.0.1:5432." ]
     then
       echo "Postgres port 5432 is listening."
   else 
     echo "ERROR:`date` Postgres port 5432 NOT listening. Ncat check FAILED."
     echo "Attempting to restart..."
     systemctl restart $POSTGRESQL
     #exit 1
   fi
   rm -f /tmp/ncoutput.out
   echo "$FUNCNAME: done"
}

function check_tomcat_status ()
{
# Active: active (exited)
# Active: inactive (running)
echo "$FUNCNAME: start"
        if [ "`systemctl status tomcat | grep Active | grep active | grep running`" ]
          then
            echo "tomcat is running."
        else
           echo "ERROR:`date` Tomcat not running."
           echo "Attempting to restart..."
           systemctl stop tomcat 
           pkill -9 -u tomcat tomcat
           systemctl start tomcat 
	   #exit 1
	fi
echo "$FUNCNAME: done"
}

function check_file ()
{
	if [ -e $1 ]
	then
	   : noop # file found
	else echo "ERROR:`date` Can't read file $1"
	   echo "Aborting..."
	   exit 1
	fi
}

function show_help ()
{
        echo "$SCRIPTNAME" 
	echo "Version 1.0"
	echo "Logs are in /var/log/$SCRIPTNAME.log"
	echo "See https://issues.vecna.com/browse/POPS-14515 for details."
	echo "Option --help, -help, --h or -h will show this help info."
	echo "Option --curl_check_only will just do a curl check and nothing else."
}

function check_nfs ()
{
echo "$FUNCNAME: start"
        for x in ${TFTPBOOT_DIR[@]}
           do 
              if [ "`showmount -e localhost|grep $x |awk '{ print $1 }'`" == "$x" ]
                 then
                    echo "nfs is OK."
              else
                 echo "ERROR:`date` $x not exported."
                 echo "Attempting to restart..."
                 systemctl restart nfs 
                 #exit 1
              fi
        done
echo "$FUNCNAME: done"
}

function check_tftp ()
{
echo "$FUNCNAME: start"
        TFTP=`netstat -tulp|grep xinetd|grep tftp|wc -l`
	if [ $TFTP -ge 1 ]
        then
           echo "tftp is OK."
        else 
	   echo "ERROR:`date` Tftp not running."
           echo "Attempting to restart..."
           systemctl restart xinetd 
           #exit 1
        fi
echo "$FUNCNAME: done"
}

# check_app_status option 
if [ "$1" = "--curl_check_only" ]; then
        logstart # start logging to $FILELOG
        check_app_status	
        exit 0
fi

# check for help option at command line 
if [ "$1" = "-h" ] || [ "$1" = "-help" ] || [ "$1" = "--h" ] || [ "$1" = "--help" ]; then
	show_help
        exit 0
fi

#############################################################################
#                            m a i n   ( )
#############################################################################
logstart                # start logging to $FILELOG
check_root_user         # more for testing since we can specify root user in cron
check_nc                # is Ncat package installed?
check_dns               # dig dns check for ipxe booting and general network use
check_nfs               # showmount nfs check for kiosk booting
check_tftp              # xinetd tftp listening?
check_postgres_port     # port 5432 listening? 
check_postgres_status   # systemctl check
check_tomcat_status     # sysetmctl check
check_app_port          # port 443 listening?
echo "*** Vecna Monitor Tomcat DONE `date +"%b %e %R:%S" `***" 
echo "########################################################"
