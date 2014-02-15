# Intro

ColorUtils is a module for BarnOwl written by asedeno to make managing
color filters easy.

Once you have ColorUtils loaded, three new command will be added to barnowl:

 * setcolor -- set the color for the current message; bound to 'c'.
 * savecolors -- persist the current color settings to file.
 * loadcolors -- load color settings from file.

{{{
setcolor [-b] [-i] <color>

-b -- set the background color, rather than the foreground color
-i -- For zephyr classes, color the particular instance. This is the default for class message.
color -- one of the colors listed in :show colors
}}}

**Note:** Colors are only persisted when the savecolors command is run, not when setcolor is used.

color settings are stored in two files in ~/.owl/

 * colormap -- foreground color mappings.
 * colormap_bg -- background color mappings.

The ColorUtils source is available through git at ​git://asedeno.mit.edu/ColorUtils.git .



