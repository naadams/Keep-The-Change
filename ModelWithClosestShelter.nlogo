extensions [gis nw]
globals [
  roads-dataset
  shelters-data
  ev-times
  tsunami
  tick_to_sec    ; ticks to seconds - usually 1
  min_lon        ; minimum longitude that is associated with min_xcor
  min_lat        ; minimum latitude that is associated with min_ycor
  areas
  ev_times
  elevation
  scale-factor
]

breed [ nodes node ]
breed [ persons person ]
breed [tourists tourist]
undirected-link-breed [ roads road ]

roads-own [      ; the variables that roads own
  mid-x          ; xcor of the middle point of a link, in patches
  mid-y          ; ycor of the middle point of a link, in patches
 ]

links-own[
  weight
]

persons-own [
  speed
  current-location
  next-node
  mypath
  destination
  evacuated?
  moving?
  dead?
  miltime
]

tourists-own [
  speed
  current-location
  next-node
  mypath
  destination
  evacuated?
  moving?
  dead?
  miltime
]

nodes-own [
  shelter?
  evac-count
  dest
  destroyed?
  ]

patches-own [    ; the variables that patches own
  flooded?
  elev
  cell-type
]

to setup
  clear-all
  reset-ticks
  gis:load-coordinate-system "elevation/elevation_data.prj"
  set elevation gis:load-dataset "elevation.asc"
  gis:apply-raster elevation elev
  set roads-dataset gis:load-dataset "roads/updatedroads.shp"
  set shelters-data gis:load-dataset "shelters/Shelters.shp"
  set areas gis:load-dataset "region/onjuku.asc"
  gis:apply-raster areas cell-type
  let world_envelope (gis:envelope-of roads-dataset)
  let netlogo_envelope (list (min-pxcor + 1) (max-pxcor - 1) (min-pycor + 1) (max-pycor - 1))             ; read the size of netlogo world
  gis:set-transformation (world_envelope) (netlogo_envelope)
  set scale-factor .3
  set tick_to_sec 1.0                                                                                     ; tick_to_sec ratio is set to 1.0 (preferred)
  set ev_times []
  ;set MTSigma 1.65  ; default values for the milling time and sigma. This means 99% of agents
  ;set MillingTime 5 ; evacuate within 5 minutes of the Milling Time that is set.
  colour-elevation-patches
  make-road-network
  setup-shelters
  create-population
  weighted-distance
  ;import-drawing "onjuku2.jpg"
end

to colour-elevation-patches
  ask patches [
    set flooded? false
    let value gis:raster-sample elevation patch pxcor pycor
    if pcolor = 0 [ set pcolor 62]
    if value <= 150 [ set pcolor 62 ]
    if value <= 50 [ set pcolor 62.5 ]
    if value <= 20 [ set pcolor 63 ]
    if value <= 14 [ set pcolor 63.5 ]
    if value <= 12 [ set pcolor 64]
    if value <= 10 [ set pcolor 64.5 ]
    if value <= 8 [ set pcolor 65 ]
    if value <= 6 [ set pcolor 65.5 ]
    if value <= 4 [ set pcolor 66 ]
    if value <= 2 [ set pcolor 66.5 ]
    if value <= 0 [ set pcolor 9] ; creates a little white beach area along the coast
    if value <= 0 and cell-type != 1 and cell-type != 2 and cell-type != 5 and cell-type != 6 [ set pcolor sky ] ; represents the water along the coast
]
end

to setup-shelters
  ; set the defaults for the shelters
  ask nodes [
    set shelter? false
    set destroyed? false
    set color black
    set size .01
]
  ; start loading the shelters
  foreach gis:feature-list-of shelters-data [ i ->     ; iterate through the shelters
    foreach gis:vertex-lists-of i [ j ->
      foreach j [ k ->
        if length ( gis:location-of k ) = 2 [              ; check if the vertex has both x and y
          let x item 0 gis:location-of k
          let y item 1 gis:location-of k
          ask min-one-of nodes [distancexy x y][   ; turn the closest node to (x,y) to a shelter
            set shelter? true
            set shape "pentagon"
            set size 3
            st
          ]
        ]
      ]
    ]
  ]
  output-print "Shelters Loaded"
end

to make-road-network
  let first-node nobody
  let previous-node nobody
  foreach gis:feature-list-of roads-dataset [ i -> ; iterate through the polyline features in the roads-dataset
    foreach gis:vertex-lists-of i [ j -> ; this creates links for each polyline and nodes at either verticies of the individual polylines
      let prev -1
      foreach j [k -> ; each coordinate
        if length ( gis:location-of k ) = 2 [                                          ; check if the vertex is valid with both x and y values
          let x item 0 gis:location-of k                                               ; get x and y values for the node
          let y item 1 gis:location-of k
          let curr 0
          ifelse any? nodes with [xcor = x and ycor = y][                      ; check if there is a node here, if not, make one, and if it is, use it
            set curr [who] of one-of nodes with [xcor = x and ycor = y]
          ][
          create-nodes 1 [
            set xcor x
            set ycor y
            set shelter? false
            set size 0.1
            set shape "square"
            set color black
            set curr who
            ;set hidden? true
           ]
          ]
          if prev != -1 and prev != curr [  ;create links between the nodes
              ask node prev [create-link-to node curr]
              ask node curr [create-link-to node prev]
            ]
      set prev curr
          ]
        ]
      ]
    ]

  ask links [
    set color black
  ]
end

to weighted-distance  ; takes the length of each link as a weight for calculating the shortest path with the network extension.
 foreach sort links [ the-road ->
 ask the-road [ set weight link-length ]]
end

to-report rayleigh-random [sigma] ; calculates a value based on a rayleigh distribution that is used in the milling time calculation
  report (sqrt((- ln(1 - random-float 1 ))*(2 *(sigma ^ 2))))
end

to create-population
  create-persons (residents * 0.2) [move-to one-of patches with [cell-type = 1]] ; creates proportional population distribution based on census data and places them on
  create-persons (residents * 0.08) [ move-to one-of nodes with [cell-type = 2]] ; nodes in those regions
  create-persons (residents * 0.18) [ move-to one-of patches with [cell-type = 3]]
  create-persons (residents * 0.18) [ move-to one-of patches with [cell-type = 4]]
  create-persons (residents * 0.12) [ move-to one-of patches with [cell-type = 5]]
  create-persons (residents * 0.08) [ move-to one-of nodes with [cell-type = 6]]
  create-persons (residents * 0.16) [ move-to one-of nodes with [cell-type = 7]]
  create-tourists (visiting-tourists * 0.5) [ move-to one-of patches with [cell-type = 1]]
  create-tourists (visiting-tourists * 0.1) [ move-to one-of patches with [cell-type = 4]]
  create-tourists (visiting-tourists * 0.4) [ move-to one-of patches with [cell-type = 5]]
  ask persons [
    set color 24
    set shape "person"
    set size 3
    set speed .06 ; .06 patch per tick is the equivalent of approx 1.4m/s which is a normal walking speed
    set evacuated? false
    set dead? false
    set moving? false
    set miltime ((Rayleigh-random MTSigma) + MillingTime ) * 60 / tick_to_sec ; milling time represents the amount of decision making time it takes each person to decide to evacuate
    set current-location one-of nodes with-min [ distance myself ] ; sets the current location to whatever node a person is loaded on
    set destination min-one-of nodes with [shelter?] [distance myself] ; selects the nearest shelter to the current node by distance as a destination
     ]

  ask tourists [
    set color 115
    set shape "person"
    set size 3
    set speed .06 ; .1 patch per tick is the equivalent of 1.4m/s which is a normal walking speed
    set speed random-normal speed .01
    if speed < 0.001 [set speed 0.001]
    set evacuated? false
    set dead? false
    set moving? false
    set miltime ((Rayleigh-random MTSigma) + MillingTime ) * 60 / tick_to_sec
    set current-location one-of nodes with-min [ distance myself ]
    set destination one-of nodes with [shelter?] with-min [distance myself]
  ]
end

to mark-evacuated
  if not evacuated? and not dead? and moving? [                              ; if the agents is not dead or evacuated, mark it as evacuated and set proper characteristics
    set color 47
    set moving? false
    set evacuated? true
    set dead? false
    set ev_times lput ( ticks * tick_to_sec / 60 ) ev_times
;    ask current-location[set evac-count evac-count + 1]
  ]
end

to mark-dead                                                     ; mark the agent dead and set proper characteristics
  set color red
  set moving? false
  set evacuated? false
  set dead? true
end

to mark-stranded
  set color pink
  set evacuated? false
  set dead? false
  set moving? false
end

to move
  if current-location = destination [mark-evacuated] ; if the person is at their destination before getting hit by the tsunami mark them evacuated
  if pcolor = sky and flooded? = true and evacuated? = false [mark-dead] ; if the person is standing on a flooded patch mark them dead
  if color = pink [set moving? false]
  ;let front-patches patches in-cone 3 90 ; after the tsunami has passed this will allow people with paths that don't intersect the flooded region to keep evacuating
  ;if [flooded?] of one-of front-patches = true and dead? = false and moving? = true and ticks >= (Warning-Time) [mark-stranded]
  if moving? [
    let front-patches patches in-cone 3 90 ; after the tsunami has passed this will allow people with paths that don't intersect the flooded region to keep evacuating
    if [flooded?] of one-of front-patches = true and dead? = false and moving? = true and ticks >= (Warning-Time) [mark-stranded]
    set next-node item 1 [ nw:turtles-on-weighted-path-to  [destination]  of myself weight] of current-location ; use the network extension to calculate the shortest distance
    ; from the current node to the destination node.  Then index the path on each iteration to move from node to node
    set heading towards next-node ; face the next node in the path
    ifelse speed > distance next-node [fd distance next-node][fd speed] ; move towards the next node the distance away it is and at the assigned speed
    if (distance next-node < 0.001)[ ; the speed in this case is scaled down to represent real world movement based on a calculation of how many meters are in a patch
      set current-location next-node ; update your current location to the next node in the list
     ]
  ]
end

to start-tsunami
  if ticks > (Warning-Time * 60)   ; wait for time specified by the user (in minutes) seconds before tsunami starts
  [ask patches with [pcolor = sky ]
  [ask patches in-radius 1 with [elev <= wave-height] [set pcolor sky ]
   set flooded? true ]    ; if patches within 1 patches are not sky, turn to the color sky.
    ; This is how the tsunami moves, depedning on the wave-height set by the user the tsunami will appear to crawl through the town at one patch per tick
    ; until it hits an elevation that is greater than the wave height
  ]
end

to go
  ask persons with [not evacuated? and not moving? and not dead? and miltime <= ticks][
    set moving? true
  ] ; initialize the people in the simulation to start moving after the mill time has passed
  ask tourists with [not evacuated? and not moving? and not dead? and miltime <= ticks][
    set moving? true
  ]
  ask persons [move] ; if a person's mill time has passed start moving them towards the destination shelter
  ask tourists [move]
  start-tsunami
  if ticks >= ((Warning-Time * 60) + 3600)[stop]  ; stops simulation an hour after the tsunami comes through, giving people with clear paths a chance to evacuate
tick

end
@#$#@#$#@
GRAPHICS-WINDOW
217
10
1128
502
-1
-1
3.0
1
10
1
1
1
0
0
0
1
-150
150
-80
80
1
1
1
ticks
30.0

BUTTON
41
10
104
43
NIL
setup
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

BUTTON
121
10
184
43
NIL
go
T
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

SLIDER
35
52
207
85
residents
residents
0
7500
7450.0
10
1
NIL
HORIZONTAL

SLIDER
35
108
207
141
visiting-tourists
visiting-tourists
0
500
170.0
10
1
NIL
HORIZONTAL

MONITOR
15
339
155
384
% Evacuated
(count turtles with [ color = 47 ] /  (count persons + count tourists) * 100)
2
1
11

SLIDER
33
146
205
179
Wave-Height
Wave-Height
1
30
5.0
1
1
meters
HORIZONTAL

INPUTBOX
0
212
73
272
MTSigma
8.0
1
0
Number

SLIDER
10
181
221
214
Warning-Time
Warning-Time
0
120
120.0
1
1
minutes
HORIZONTAL

MONITOR
10
439
199
496
Time Elapsed (in Minutes)
ticks / 60
1
1
14

MONITOR
21
292
125
337
% Stranded
(count turtles with [ color = pink ] /  (count persons + count tourists) * 100)
2
1
11

MONITOR
32
386
122
431
% Dead
(count turtles with [ color = red ] /  (count persons + count tourists) * 100)
2
1
11

INPUTBOX
80
217
160
277
MillingTime
0.0
1
0
Number

PLOT
1137
38
1486
314
Evacuation Times 
Minutes after Warning
# Evacuated
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 1 -16777216 true "set-plot-x-range 0 60\nset-plot-y-range 0 count turtles with [ color = 47 ]\nset-histogram-num-bars 60\nset-plot-pen-mode 1 ; bar mode" "histogram ev_times"

@#$#@#$#@
## WHAT IS IT?
This is a tsunami evacuation simulation for the city of Onjuku, Japan.  It's intention is to show how human decision making and different warning times can effect the rate of casualties during a tsunami event.  

## HOW IT WORKS
The model makes use of both the GIS and network extensions in Netlogo.  First the GIS extension is used to load an elevation raster of Onjuku that will dictate where the tsunami is allowed to travel to.  Then the road network and shelter locations are imported as shapefiles and broken down into links and nodes that the agents can move around on.  They use the network extension to calculate the shortest path to the closest shelter to their initial location.  They then move at either a normal walking speed (if a resident) or a randomly assigned speed using a value taken from normal distribution around a normal walking speed (tourist)  As the tsunami event progresses agents are either marked as evactuated if they reach a shelter before a patch they are standing on becomes flooded, marked as dead if they are stood on a flooded patch, or marked as stranded if not stood on a flooded patch but unable to make it to a shelter.  

## HOW TO USE IT
When the model first starts it is assumed that moment a tsunami alarm is going off. You can adjust the population sliders to reflect whatever type of population scenario you wish.  Onjuku is known for a nice beach and gets some tourist activity in the summer times so a small percentage of the evacuees can be set to tourists.  The Wave-Height parameter allows you to choose a tsunami of varying strengths, and the warning time indicates how long will elapse before the tsunami hits the shore. By adjusting the Milling Time you can change how long the evacuees will wait before making a decsion.  The sigma value will determine the spread of values that can be assigned.  A default value to consider is 5 minutes and a sigma value of 1.65 as this indicates that 99% of people will have begun evacuating between 5-10 minutes into the simulation 
## THINGS TO NOTICE
You can see areas of Onkjuku that emerge as parts of the city that consistently have people getting caught by the tsunami.  These could be parts of the city to consider adding shelters to potentially.  There are also outputs indicating rates of evacuation, death and stranded.  By adjusting the sliders you can see how these values change given different parameters.

## THINGS TO TRY
See things to notice

## EXTENDING THE MODEL
The model could be improved upon by adding different modes of transport or including a traffic model of some sort.  As it stands agents are able to occupy the same space at the same time and can only walk at one constant speed.

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES
Credit goes to Mostafizi, Alireza at Oregon State for exerpts of the code used in this model.
@#$#@#$#@
default
true
0
Polygon -7500403 true true 150 5 40 250 150 205 260 250

airplane
true
0
Polygon -7500403 true true 150 0 135 15 120 60 120 105 15 165 15 195 120 180 135 240 105 270 120 285 150 270 180 285 210 270 165 240 180 180 285 195 285 165 180 105 180 60 165 15

arrow
true
0
Polygon -7500403 true true 150 0 0 150 105 150 105 293 195 293 195 150 300 150

box
false
0
Polygon -7500403 true true 150 285 285 225 285 75 150 135
Polygon -7500403 true true 150 135 15 75 150 15 285 75
Polygon -7500403 true true 15 75 15 225 150 285 150 135
Line -16777216 false 150 285 150 135
Line -16777216 false 150 135 15 75
Line -16777216 false 150 135 285 75

bug
true
0
Circle -7500403 true true 96 182 108
Circle -7500403 true true 110 127 80
Circle -7500403 true true 110 75 80
Line -7500403 true 150 100 80 30
Line -7500403 true 150 100 220 30

butterfly
true
0
Polygon -7500403 true true 150 165 209 199 225 225 225 255 195 270 165 255 150 240
Polygon -7500403 true true 150 165 89 198 75 225 75 255 105 270 135 255 150 240
Polygon -7500403 true true 139 148 100 105 55 90 25 90 10 105 10 135 25 180 40 195 85 194 139 163
Polygon -7500403 true true 162 150 200 105 245 90 275 90 290 105 290 135 275 180 260 195 215 195 162 165
Polygon -16777216 true false 150 255 135 225 120 150 135 120 150 105 165 120 180 150 165 225
Circle -16777216 true false 135 90 30
Line -16777216 false 150 105 195 60
Line -16777216 false 150 105 105 60

car
false
0
Polygon -7500403 true true 300 180 279 164 261 144 240 135 226 132 213 106 203 84 185 63 159 50 135 50 75 60 0 150 0 165 0 225 300 225 300 180
Circle -16777216 true false 180 180 90
Circle -16777216 true false 30 180 90
Polygon -16777216 true false 162 80 132 78 134 135 209 135 194 105 189 96 180 89
Circle -7500403 true true 47 195 58
Circle -7500403 true true 195 195 58

circle
false
0
Circle -7500403 true true 0 0 300

circle 2
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240

cow
false
0
Polygon -7500403 true true 200 193 197 249 179 249 177 196 166 187 140 189 93 191 78 179 72 211 49 209 48 181 37 149 25 120 25 89 45 72 103 84 179 75 198 76 252 64 272 81 293 103 285 121 255 121 242 118 224 167
Polygon -7500403 true true 73 210 86 251 62 249 48 208
Polygon -7500403 true true 25 114 16 195 9 204 23 213 25 200 39 123

cylinder
false
0
Circle -7500403 true true 0 0 300

dot
false
0
Circle -7500403 true true 90 90 120

face happy
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 255 90 239 62 213 47 191 67 179 90 203 109 218 150 225 192 218 210 203 227 181 251 194 236 217 212 240

face neutral
false
0
Circle -7500403 true true 8 7 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Rectangle -16777216 true false 60 195 240 225

face sad
false
0
Circle -7500403 true true 8 8 285
Circle -16777216 true false 60 75 60
Circle -16777216 true false 180 75 60
Polygon -16777216 true false 150 168 90 184 62 210 47 232 67 244 90 220 109 205 150 198 192 205 210 220 227 242 251 229 236 206 212 183

fish
false
0
Polygon -1 true false 44 131 21 87 15 86 0 120 15 150 0 180 13 214 20 212 45 166
Polygon -1 true false 135 195 119 235 95 218 76 210 46 204 60 165
Polygon -1 true false 75 45 83 77 71 103 86 114 166 78 135 60
Polygon -7500403 true true 30 136 151 77 226 81 280 119 292 146 292 160 287 170 270 195 195 210 151 212 30 166
Circle -16777216 true false 215 106 30

flag
false
0
Rectangle -7500403 true true 60 15 75 300
Polygon -7500403 true true 90 150 270 90 90 30
Line -7500403 true 75 135 90 135
Line -7500403 true 75 45 90 45

flower
false
0
Polygon -10899396 true false 135 120 165 165 180 210 180 240 150 300 165 300 195 240 195 195 165 135
Circle -7500403 true true 85 132 38
Circle -7500403 true true 130 147 38
Circle -7500403 true true 192 85 38
Circle -7500403 true true 85 40 38
Circle -7500403 true true 177 40 38
Circle -7500403 true true 177 132 38
Circle -7500403 true true 70 85 38
Circle -7500403 true true 130 25 38
Circle -7500403 true true 96 51 108
Circle -16777216 true false 113 68 74
Polygon -10899396 true false 189 233 219 188 249 173 279 188 234 218
Polygon -10899396 true false 180 255 150 210 105 210 75 240 135 240

house
false
0
Rectangle -7500403 true true 45 120 255 285
Rectangle -16777216 true false 120 210 180 285
Polygon -7500403 true true 15 120 150 15 285 120
Line -16777216 false 30 120 270 120

leaf
false
0
Polygon -7500403 true true 150 210 135 195 120 210 60 210 30 195 60 180 60 165 15 135 30 120 15 105 40 104 45 90 60 90 90 105 105 120 120 120 105 60 120 60 135 30 150 15 165 30 180 60 195 60 180 120 195 120 210 105 240 90 255 90 263 104 285 105 270 120 285 135 240 165 240 180 270 195 240 210 180 210 165 195
Polygon -7500403 true true 135 195 135 240 120 255 105 255 105 285 135 285 165 240 165 195

line
true
0
Line -7500403 true 150 0 150 300

line half
true
0
Line -7500403 true 150 0 150 150

pentagon
false
0
Polygon -7500403 true true 150 15 15 120 60 285 240 285 285 120

person
false
0
Circle -7500403 true true 110 5 80
Polygon -7500403 true true 105 90 120 195 90 285 105 300 135 300 150 225 165 300 195 300 210 285 180 195 195 90
Rectangle -7500403 true true 127 79 172 94
Polygon -7500403 true true 195 90 240 150 225 180 165 105
Polygon -7500403 true true 105 90 60 150 75 180 135 105

plant
false
0
Rectangle -7500403 true true 135 90 165 300
Polygon -7500403 true true 135 255 90 210 45 195 75 255 135 285
Polygon -7500403 true true 165 255 210 210 255 195 225 255 165 285
Polygon -7500403 true true 135 180 90 135 45 120 75 180 135 210
Polygon -7500403 true true 165 180 165 210 225 180 255 120 210 135
Polygon -7500403 true true 135 105 90 60 45 45 75 105 135 135
Polygon -7500403 true true 165 105 165 135 225 105 255 45 210 60
Polygon -7500403 true true 135 90 120 45 150 15 180 45 165 90

sheep
false
15
Circle -1 true true 203 65 88
Circle -1 true true 70 65 162
Circle -1 true true 150 105 120
Polygon -7500403 true false 218 120 240 165 255 165 278 120
Circle -7500403 true false 214 72 67
Rectangle -1 true true 164 223 179 298
Polygon -1 true true 45 285 30 285 30 240 15 195 45 210
Circle -1 true true 3 83 150
Rectangle -1 true true 65 221 80 296
Polygon -1 true true 195 285 210 285 210 240 240 210 195 210
Polygon -7500403 true false 276 85 285 105 302 99 294 83
Polygon -7500403 true false 219 85 210 105 193 99 201 83

square
false
0
Rectangle -7500403 true true 30 30 270 270

square 2
false
0
Rectangle -7500403 true true 30 30 270 270
Rectangle -16777216 true false 60 60 240 240

star
false
0
Polygon -7500403 true true 151 1 185 108 298 108 207 175 242 282 151 216 59 282 94 175 3 108 116 108

target
false
0
Circle -7500403 true true 0 0 300
Circle -16777216 true false 30 30 240
Circle -7500403 true true 60 60 180
Circle -16777216 true false 90 90 120
Circle -7500403 true true 120 120 60

tree
false
0
Circle -7500403 true true 118 3 94
Rectangle -6459832 true false 120 195 180 300
Circle -7500403 true true 65 21 108
Circle -7500403 true true 116 41 127
Circle -7500403 true true 45 90 120
Circle -7500403 true true 104 74 152

triangle
false
0
Polygon -7500403 true true 150 30 15 255 285 255

triangle 2
false
0
Polygon -7500403 true true 150 30 15 255 285 255
Polygon -16777216 true false 151 99 225 223 75 224

truck
false
0
Rectangle -7500403 true true 4 45 195 187
Polygon -7500403 true true 296 193 296 150 259 134 244 104 208 104 207 194
Rectangle -1 true false 195 60 195 105
Polygon -16777216 true false 238 112 252 141 219 141 218 112
Circle -16777216 true false 234 174 42
Rectangle -7500403 true true 181 185 214 194
Circle -16777216 true false 144 174 42
Circle -16777216 true false 24 174 42
Circle -7500403 false true 24 174 42
Circle -7500403 false true 144 174 42
Circle -7500403 false true 234 174 42

turtle
true
0
Polygon -10899396 true false 215 204 240 233 246 254 228 266 215 252 193 210
Polygon -10899396 true false 195 90 225 75 245 75 260 89 269 108 261 124 240 105 225 105 210 105
Polygon -10899396 true false 105 90 75 75 55 75 40 89 31 108 39 124 60 105 75 105 90 105
Polygon -10899396 true false 132 85 134 64 107 51 108 17 150 2 192 18 192 52 169 65 172 87
Polygon -10899396 true false 85 204 60 233 54 254 72 266 85 252 107 210
Polygon -7500403 true true 119 75 179 75 209 101 224 135 220 225 175 261 128 261 81 224 74 135 88 99

wheel
false
0
Circle -7500403 true true 3 3 294
Circle -16777216 true false 30 30 240
Line -7500403 true 150 285 150 15
Line -7500403 true 15 150 285 150
Circle -7500403 true true 120 120 60
Line -7500403 true 216 40 79 269
Line -7500403 true 40 84 269 221
Line -7500403 true 40 216 269 79
Line -7500403 true 84 40 221 269

wolf
false
0
Polygon -16777216 true false 253 133 245 131 245 133
Polygon -7500403 true true 2 194 13 197 30 191 38 193 38 205 20 226 20 257 27 265 38 266 40 260 31 253 31 230 60 206 68 198 75 209 66 228 65 243 82 261 84 268 100 267 103 261 77 239 79 231 100 207 98 196 119 201 143 202 160 195 166 210 172 213 173 238 167 251 160 248 154 265 169 264 178 247 186 240 198 260 200 271 217 271 219 262 207 258 195 230 192 198 210 184 227 164 242 144 259 145 284 151 277 141 293 140 299 134 297 127 273 119 270 105
Polygon -7500403 true true -1 195 14 180 36 166 40 153 53 140 82 131 134 133 159 126 188 115 227 108 236 102 238 98 268 86 269 92 281 87 269 103 269 113

x
false
0
Polygon -7500403 true true 270 75 225 30 30 225 75 270
Polygon -7500403 true true 30 75 75 30 270 225 225 270
@#$#@#$#@
NetLogo 6.1.1
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
@#$#@#$#@
default
0.0
-0.2 0 0.0 1.0
0.0 1 1.0 0.0
0.2 0 0.0 1.0
link direction
true
0
Line -7500403 true 150 150 90 180
Line -7500403 true 150 150 210 180
@#$#@#$#@
0
@#$#@#$#@
