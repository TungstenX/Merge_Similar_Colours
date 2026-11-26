# Merge Similar Colours

## Description
This script will merge similar colours of a sprite's palette. Here, similar colours means colours that are close, by percentage, to other colours. It will then merge these colours in the palette to reduce the colour count of the palette


## Install

In Aseprite (tested on v1.3.18.6):

* Open script folder by going to File -> Scripts -> Open Script Folder
* Copy Merge_Similar_Colours.lua to that script folder
* Rescan script folder File -> Scripts -> Rescan Script Folder



## Usage
1. Run script to File -> Scripts -> Merge_Similar_Colours
2. Select Distance Metric for how the script will do it's calculations.
    * RGB is fast because it uses a simple distance calculation of the individual R.G.B. components of two colours
    * [CIE LAB color](https://en.wikipedia.org/wiki/CIELAB_color_space) is more accurate as it uses perceptual colour difference calculations
4. Select the Similarity Threshold percentage
5. Switch to indexed colour mode to apply changed colour palette: Sprite -> Color Mode -> Indexed


## AI Statement
My dwarf, Ragoth, an AI agent using Gemini LLM, coded the whole script
