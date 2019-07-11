# dyntest-suite
Testing Suite for Dyninst (and friends)


## Directory Structure
```
build/ - Components nessesary for building all the bits.
external/* - External projects not technically under testing.
         */dummy/ - Dummy files intended to "act like" a proper install root.
         */find.lua - Tup-Lua script to find external projects if possible.
         */use.tup - Tupscript that appends applicable arguments for building.
src/ - Storage for the projects under testing.
    {elfutils,dyninst,hpctoolkit} - Latest versions, parallel and to be tested.
    ref-{elfutils,dyninst} - Correct reference versions, serial.
    {elfutils,dyninst,hpctoolkit}.tup - Build and dependency managements.
{latest,reference}/{elfutils,dyninst,hpctoolkit} - Build outputs.
                   dummy/ - Dummy files intended to "act like" a proper install.
                   install/ - Final install outputs for each project.
                   Tupfile - Tupfile that builds each with the proper settings.
                   use.tup - Tupscript to append applicable arguments for deps.
tests/ - Storage for the entire testing subsystem.
```
