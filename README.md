# hybris-server-manager

## Introduction

When you start a Hybris instance using ./hybrisserver.sh start, it starts Hybris in the background, but will exit immediately. In test scenarios, you often want to wait until the complete Hybris server has started with all defined Tomcat contexts. Most of the time, you will either sleep for a static amount of time or do a bunch of http request to known URLs until you get a 200 code.

This script uses the [check-tomcat](https://github.com/dodevops/check-tomcat) to actively check the tomcat server using JMX, wether all defined contexts are loaded.

This repository is currently lacking a lot of documentation, please use the source of the script for details.
