@#
@# Author: Mike Purvis <mpurvis@clearpathrobotics.com>
@#         Copyright (c) 2013-2014, Clearpath Robotics, Inc.
@#
@# Redistribution and use in source and binary forms, with or without
@# modification, are permitted provided that the following conditions are met:
@#    * Redistributions of source code must retain the above copyright
@#       notice, this list of conditions and the following disclaimer.
@#    * Redistributions in binary form must reproduce the above copyright
@#       notice, this list of conditions and the following disclaimer in the
@#       documentation and/or other materials provided with the distribution.
@#    * Neither the name of Clearpath Robotics, Inc. nor the
@#       names of its contributors may be used to endorse or promote products
@#       derived from this software without specific prior written permission.
@#
@# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
@# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
@# WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
@# DISCLAIMED. IN NO EVENT SHALL CLEARPATH ROBOTICS, INC. BE LIABLE FOR ANY
@# DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
@# (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
@# LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
@# ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
@# (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
@# SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
@#
@# Please send comments, questions, or patches to code@clearpathrobotics.com
#!/bin/bash
# THIS IS A GENERATED FILE, NOT RECOMMENDED TO EDIT.

function log() {
  logger -s -p user.$1 ${@@:2}
}

log info "@(name): Using workspace setup file @(workspace_setup)"

@[if rmw]@
export RMW_IMPLEMENTATION=@(rmw)
@[else]@
export RMW_IMPLEMENTATION=rmw_fastrtps_cpp
@[end if]@

rmw="@(rmw)"
rmw_config="@(rmw_config)"

if [[ "$rmw" == "rmw_fastrtps_cpp" ]]
then
  if [[ ! -z $rmw_config ]]
  then
    export FASTRTPS_DEFAULT_PROFILES_FILE=$rmw_config
  fi
elif [[ "$rmw" == "rmw_cyclonedds_cpp" ]]
then
  if [[ ! -z $rmw_config ]]
  then
    export CYCLONEDDS_URI=$rmw_config
  fi
fi

@[if ros_domain_id]@
export ROS_DOMAIN_ID=@(ros_domain_id)
@[end if]@

source @(workspace_setup)
JOB_FOLDER=@(job_path)

log_path="@(log_path)"
if [[ ! -d $log_path ]]; then
  CREATED_LOGDIR=true
  trap 'CREATED_LOGDIR=false' ERR
    log warn "@(name): The log directory you specified \"$log_path\" does not exist. Attempting to create."
    mkdir -p $log_path 2>/dev/null
    chown @(user):@(user) $log_path 2>/dev/null
    chmod ug+wr $log_path 2>/dev/null
  trap - ERR
  # if log_path could not be created, default to tmp
  if [[ $CREATED_LOGDIR == false ]]; then
    log warn "@(name): The log directory you specified \"$log_path\" cannot be created. Defaulting to \"/tmp\"!"
    log_path="/tmp"
  fi
fi

@[if interface]@
export ROS_IP=`ros2 run robot_upstart getifip @(interface)`
if [ "$ROS_IP" = "" ]; then
  log err "@(name): No IP address on @(interface), cannot ros2 launch."
  exit 1
fi
@[else]@
export ROS_HOSTNAME=$(hostname)
@[end if]@

export ROS_HOME=${ROS_HOME:=$(echo ~@(user))/.ros}
export ROS_LOG_DIR=$log_path

log info "@(name): Launching ROS_HOSTNAME=$ROS_HOSTNAME, ROS_IP=$ROS_IP, ROS_MASTER_URI=$ROS_MASTER_URI, ROS_HOME=$ROS_HOME, ROS_LOG_DIR=$log_path"

# If xacro files are present in job folder, generate and expand an amalgamated urdf.
XACRO_FILENAME=$log_path/@(name).xacro
XACRO_ROBOT_NAME=$(echo "@(name)" | cut -d- -f1)
ros2 run robot_upstart mkxacro $JOB_FOLDER $XACRO_ROBOT_NAME > $XACRO_FILENAME
if [[ "$?" == "0" ]]; then
  URDF_FILENAME=$log_path/@(name).urdf
  ros2 run xacro xacro $XACRO_FILENAME -o $URDF_FILENAME
  if [[ "$?" == "0" ]]; then
    log info "@(name): Generated URDF: $URDF_FILENAME"
  else
    log warn "@(name): URDF macro expansion failure. Robot description will not function."
  fi
  export ROBOT_URDF_FILENAME=$URDF_FILENAME
fi

# Assemble amalgamated launchfile.
LAUNCH_FILENAME=$log_path/@(name).launch.py
ros2 run robot_upstart mklaunch $JOB_FOLDER > $LAUNCH_FILENAME
if [[ "$?" != "0" ]]; then
  log err "@(name): Unable to generate amalgamated launchfile. $JOB_FOLDER $LAUNCH_FILENAME"
  exit 1
fi
log info "@(name): Generated launchfile: $LAUNCH_FILENAME"

# Warn and exit if setpriv is missing from the system.
which setpriv > /dev/null
if [ "$?" != "0" ]; then
  log err "@(name): Can't launch as unprivileged user without setpriv. Please install the setpriv package."
  exit 1
fi

# Punch it.
setpriv --reuid @(user) ros2 launch $LAUNCH_FILENAME @(roslaunch_wait?'--wait ')&
PID=$!

log info "@(name): Started ros2 launch as background process, PID $PID, ROS_LOG_DIR=$ROS_LOG_DIR"
echo "$PID" > $log_path/@(name).pid

wait "$PID"
