#!/bin/bash
installDir=_INSTALL_DIRECTORY
 cd ${installDir}
mystart ()
{
 rm -rf ${installDir}/var/run/rsyncd.pid
 /usr/bin/rsync --daemon --config=${installDir}etc/rsync.conf --port=7755  2>>${installDir}/var/log/rsyncd_start.log 1>>${installDir}/var/log/rsyncd_start.log
 sleep 5
 rsync_pid=`ps aux | grep '/usr/bin/rsync' | grep -v grep| awk '{print $2}'`
 echo $rsync_pid > bg.pid
}

mystart_lsyncd ()
{
 /usr/bin/lsyncd ./etc/lsyncd.conf 2>> ${installDir}var/log/lsyncd_start.log 1>>${installDir}var/log/lsyncd_start.log
 sleep 5
 lsync_pid=`ps aux | grep '/usr/bin/lsyncd' | grep -v grep| awk '{print $2}'`
 echo $lsync_pid > bg_lsyncd.pid
}

case "$1" in
 start)
   mystart
   mystart_lsyncd
 ;;
 stop)
   mypid=`cat bg.pid`
   mypid_lsyncd=`cat bg_lsyncd.pid`
   var2=`ps xu | grep $mypid | wc -l`
   var3=`ps xu | grep $mypid_lsyncd | wc -l`
   if [ "$var2" -gt 0 ]
   then
     kill $mypid
   fi
   if [ "$var3" -gt 0 ]
   then
     kill $mypid_lsyncd
   fi
   ;;
 check)
   # check if the process is running.
   mypid=`cat bg.pid`
   mypid_lsyncd=`cat bg_lsyncd.pid`
   var2=`ps aux | grep '/usr/bin/rsync' | grep -v grep | wc -l`
   var3=`ps aux | grep '/usr/bin/lsyncd' | grep -v grep | wc -l`
   if [ "$var2" -lt 1 ]
   then
     mystart
   fi
   if [ "$var3" -lt 1 ]
   then
     mystart_lsyncd
   fi
   ;;
esac

exit 0;
