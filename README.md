# BeSP

>Work in progress, ALPHA software

>Note this alpha version needs to run twice:
>first to generate bespoke .besp files (for debugging)
>second to render 


**bellasliderpreviews.sh** is a bash script 
to generate scrubbable jpeg previews of Bella node attributes. It runs natively on Linux/MacOS and on Windows using git-bash from https://git-scm.com

> Currently only some random Material nodes attribs are available. More to come...

Here is a sample
http://besp.oomer.org/23.6.0/material/directory.html


To generate html slider previews
- put a Bella scene file (.bsz, .bsx, or .bsa) in the same dir as **bellasliderpreviews.sh**
- in bash/zsh run **bash bellasliderpreviews.sh**
- select Bella scenefile
- select the scene node to modify ( ie mesh, xform )
- will render 30 frames per attribute, this will take a long time
- as an example the htmls and renders will be created in:
    - **23.6.0** dir
        - **material** dir
            - **shaderball.bsz.carPaint.flakes.size** dir 
- double click on **index.html** to see BeSP (aka Bella Slider Previews)
- double click on **directory.html** in the **material** dir to see all available **BeSPs**

**Thanks to Jeremy Hill of Diffuse Logic for javascript code to scrub jpegs.**

Run these in **bash** to set global render settings. Add your BELLA_LICENSE_TEXT to remove watermark.
```sh
export BELLA_PARSE_FRAGMENT="nncamera.resolution=vec2(320 320);nncamera.region=null;nnbeautyPass.targetNoise=7u;nnbeautyPass.saveImage=0;nnbeautyPass.outputExt=\".jpg\";"
export BELLA_VERSION="23.6.0"
```