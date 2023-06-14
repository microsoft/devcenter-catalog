param(
     [Parameter()]
     [string]$command
 )

# We are adding this file as an additional layer
# between the devbox.yaml file invoking this task
# and the actual execution of the command.
# The main goal is to ensure we do any additional
# I/O and security checks here ahead of running
# the command on the metal.
iex $command
