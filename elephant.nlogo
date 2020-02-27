;; Elephant Poaching ABM ;;

extensions [ csv ]

breed [ waters water ]
breed [ villages village ]
breed [ elephants elephant ]
breed [ herds herd ]
breed [ poachers poacher ]

globals [
  caught-by-poacher
]

turtles-own [
  nearest-poacher
  nearest-elephant
]

breed [zones zone]

herds-own [ my-water ]

zones-own [
  my-patches
  num-times-visited-by-poachers
  num-times-poachers-caught
  probability-of-catching-poacher
]

undirected-link-breed [ zone-links zone-link ]

zone-links-own [
  num-elephants-seen
  num-times-visited
]

elephants-own [
  gender
  age
  max-age
  status
  nearest-neighbor
]

undirected-link-breed [ herd-memberships herd-membership ]

poachers-own [
  number-catches
  lifetime-catches
  count-down
  number-of-trips
]

patches-own [
  countdown
  zone-here
]

to setup
  clear-all

  if load-params-from-file? [ setup-sobol ]

  resize-world -20 20 -20 20                         ;; resize world so the grid fits evenly in it

  set-default-shape elephants "mammoth"
  set-default-shape waters "circle"
  set-default-shape villages "house"

  ;; create village ;;;
  ask patch -10 15 [
    sprout-villages 1 [
      set color yellow
      set size 2
    ]
  ]

  ; create water

  setup-zones
  setup-elephants
  setup-poachers

  reset-ticks
end

to setup-sobol

  let lines csv:from-file "sobol_emily.csv"
  let line item param-line-to-use lines

  set initial-number-elephants item 0 line
  set exploration-prob item 1 line
  set number-of-herds item 2 line
  set poacher-goodness item 3 line
  set overall-patrol-probability item 4 line
  set initial-number-poacher item 5 line

end

to setup-zones ;; draw zones

  create-zones 4
  let sorted-zones sort zones

  ask item 0 sorted-zones [
    set my-patches patches with [pxcor >= 0 and pycor >= -20 and pycor <= 0]
    ask my-patches [
      set pcolor green - 2 + random-float 1
    ]
    ask n-of 1 my-patches
    [
      sprout-waters 1
    ]
  ]

  ask item 1 sorted-zones [
    set my-patches patches with [pxcor >= 0 and pycor >= 0]
    ask my-patches [
      set pcolor green + random-float 1
    ]
  ]

  ask item 2 sorted-zones [
    set my-patches patches with [pxcor >= -20 and pxcor <= 0 and pycor >= -20 and pycor <= 0]
    ask my-patches [
      set pcolor green + random-float 1
    ]
    ask n-of 2 my-patches
    [
      sprout-waters 1
    ]
  ]

  ask item 3 sorted-zones [
    set my-patches patches with [pxcor >= -20 and pxcor <= 0 and pycor >= 0]
    ask my-patches [
      set pcolor green - 2 + random-float 1
    ]
  ]

  ask zones [
    hide-turtle
    ask my-patches [ set zone-here myself ]

  ]

  ask waters  [
    set color blue
    set size 2
  ]

end

to setup-elephants
  create-herds number-of-herds [
    set my-water one-of waters
    hide-turtle
  ]
  ; create the required number of elephants, given that herds are each going to also create one
  create-elephants (initial-number-elephants - number-of-herds) [
    setup-elephant
    create-herd-membership-with one-of herds [ hide-link ]
  ]
  ask herds [
    hatch-elephants 1 [
      ; ensure there is at least one female in the herd
      setup-elephant
      set gender "female"
      set color white
      create-herd-membership-with myself [ hide-link ]
    ]
    ; turn the oldest female in the herd into a matriarch
    ask max-one-of (herd-members with [ gender = "female" ]) [ age ] [
      set color red
      set status "matriarch"
    ]
  ]
  ask elephants with [ status != "matriarch" ] [
    move-to my-matriarch
    forward random-float 1
  ]
end

to setup-elephant
  set age random-in-range 0 60
  set max-age 60
  set gender one-of ["male" "female"]
  set color ifelse-value gender = "male" [ black ] [ white ]
  set size 1
  setxy random-xcor random-ycor
  set status "follower" ; status of elephants are either "follower" or "matriarch"
end

to-report my-herd
  report one-of herd-membership-neighbors
end

to-report my-herdmates
  report other [ herd-membership-neighbors ] of my-herd
end

to-report my-matriarch
  report one-of my-herdmates with [ status = "matriarch" ]
end

to-report herd-members ; herd report
  report herd-membership-neighbors
end

to setup-poachers
  set-default-shape poachers "person"
  create-poachers initial-number-poacher ; create the people
  [
    set color 45
    set size 1
    move-to one-of villages            ;; set their location as the village
                                       ;; can raise or lower this depending on equipment / technology (i.e. on-foot vs. helicopters)
    set count-down random 10
    set number-of-trips 0
    create-zone-links-with zones [hide-link]
  ]
end

to-report random-in-range [low high]
  report low + random (high - low + 1)
end

to go
  if not any? poachers [ stop ]
  if not any? elephants [ stop ]
  if ticks = 3650 [stop]

  ask elephants [
    move-elephant
    death
    if ticks mod 365 = 0
    [
      set age age + 1
      reproduce-elephant
    ]
  ]

  ask poachers
  [
    set count-down count-down - 1

    if count-down = 0 [
      ifelse in-village? [
        start-poaching-trip
        ( ifelse
          poacher-movement = "random" [  visit-zone one-of zones ]
          poacher-movement = "adaptive" [ adaptive-poacher]
        )
        catch-elephants
        die-poacher
      ] [
        move-to one-of villages
        set count-down 5 + random 5
      ]
    ]
  ]


  if law-enforcement-strategy = "follow herds" [ follow-elephants ]
  if law-enforcement-strategy = "follow schedule" [ follow-schedule ]


  tick
end

to move-elephant
  (ifelse
    status = "matriarch" [ move-as-matriarch ]
    gender = "male" and age >= 14 [ move-randomly ]
    [ follow-matriarch ]
  )
end

to move-randomly
  rt random 20 - 10
  fd 1
end

to follow-matriarch
  let the-matriarch my-matriarch
  ifelse the-matriarch != nobody [
    move-to the-matriarch
    forward random-float 2
  ] [
    move-randomly
  ]
end

to move-as-matriarch

  ; seasonality
  ; Jan-Feb = dry season. Ticks 0-59/365. Face water
  ; March-May = rainy season. Ticks 60-151. Move randomly
  ; June- Oct = dry. Ticks 152-304. Face water
  ; Nov-Dec = rainy. Ticks 305-365. Move randomly

  ifelse (ticks mod 365 < 59) or (ticks mod 365 > 151) and (ticks mod 365 < 305) [
    if patch-here != [ my-water ] of my-herd [
      face [ my-water ] of my-herd
      fd 1
    ]
  ] [
    move-randomly
  ]

end

to reproduce-elephant
  ; give birth in every 6 years after certain age
  if gender = "female" and age >= 13 and random-float 1 < 0.20
    [

      ;; some default values
      let offspring-gender "male"
      let offspring-color black

      if random 2 = 1      ;; initial gender distribution is 50%
        [
          set offspring-gender "female"
          set offspring-color white
      ]

      ;; hello world
      hatch 1 [
        set age 1
        create-herd-membership-with [my-herd] of myself [ hide-link ]
        set gender offspring-gender
        set color offspring-color
        set status "follower"

      ]
  ]
  if count elephants with [ gender = "male" ] = 0 or count elephants with [ gender = "female" ] = 0 [ stop ]

end


to death  ; turtle procedure
          ; with random probability and/or max age, die
  if age > max-age
    [
      ifelse status = "matriarch"
      [death-matriarch]
      [die]
  ]
end

to death-matriarch

  let herdmates my-herdmates

  ; pick a new matriarch
  let new_matriarch  one-of (herdmates with [gender = "female"]) with-max [age]
  ;;ask the matriarch to change color
  if new_matriarch != nobody [
    ask new_matriarch
    [
      ;;change its color, age, status
      set color red
      set status "matriarch"
    ]
  ]

  die


end


to start-poaching-trip
  set number-of-trips number-of-trips + 1
  set count-down 3

end

to die-poacher
  ; people procedure
  if not in-village? [
    let p [ probability-of-catching-poacher ] of zone-here
    if(random-float 1 < p) [
      ask zone-here [set num-times-poachers-caught num-times-poachers-caught + 1 ]
      die
    ]
  ]
end


to visit-zone [ target-zone ]
  move-to [ one-of my-patches ] of target-zone
  ask zone-link-with target-zone [ set num-times-visited num-times-visited + 1
  ]
  ask zone-here [ set num-times-visited-by-poachers num-times-visited-by-poachers + 1]

end


to follow-schedule
  let day-of-the-week ticks mod 7

  ;;;; if the ranger schedule occurs on a set number of days (once a week)

  ifelse day-of-the-week = 3 [
    let patrolling-probabilities map [ p -> p * overall-patrol-probability ] [0.5 0.1 0.05 0.35]
    (foreach (sort zones) patrolling-probabilities [ [the-zone the-probability] ->
      ask the-zone [ set probability-of-catching-poacher the-probability ]
    ])
  ] [
    ask zones [ set probability-of-catching-poacher 0 ]
  ]

end

to adaptive-poacher

  let destination-zone
    [other-end] of one-of my-zone-links with-max [
      (num-elephants-seen / (num-times-visited + 1)) -
      ([num-times-poachers-caught / (num-times-visited-by-poachers + 1) ] of other-end)
  ]

  visit-zone ifelse-value (number-of-trips <= 5 or random 100 < exploration-prob) [
    one-of zones
  ] [
    destination-zone
  ]

  ; print destination-zone
end

to follow-elephants
  ; count the number of matriarchs in each zone
  ; make ranger effort = number of matriarchs in that box divided by the total number of matriarchs
  ; when there are no matriarchs anywhere, put all effort to zero
  ; rangers are essentially following their migration routes

  let day-of-the-week ticks mod 7
  let total count elephants with [status = "matriarch" ]
  ifelse day-of-the-week = 3  and total > 0[
    ask zones [
      let matriarchs-here sum [ count elephants-here with [status = "matriarch"] ] of my-patches
      set probability-of-catching-poacher ((matriarchs-here / total) * overall-patrol-probability)
    ]
  ] [
    ask zones [ set probability-of-catching-poacher 0 ]
  ]
end

to-report in-village? ; turtle reporter
  report any? villages-here
end

to catch-elephants

  ; Catching elephants

  let prey one-of elephants-here
  if prey != nobody [
    ask zone-link-with zone-here [ set num-elephants-seen num-elephants-seen + 1 ]

    if random-float 1 < poacher-goodness
    [
      set caught-by-poacher caught-by-poacher + 1
      set number-catches number-catches + 1
      set lifetime-catches lifetime-catches + 1
    ]


    ask prey
    [
      ifelse status = "follower" [die]
      [
        if status = "matriarch"
        [
          death-matriarch
        ]
      ]
    ]
  ]


end


;;; for plotting ;;;


to-report mean-age-females
  ifelse count elephants with [ gender = "female" ] > 0 [
    report mean [ age ] of elephants with [ gender = "female" ]
  ]
  [ report 0 ]
end


to-report mean-age-males
  ifelse count elephants with [ gender = "male" ] > 0 [
    report mean [ age ] of elephants with [ gender = "male" ]
  ]
  [ report 0 ]
end

to-report count-females
  ifelse count elephants with [ gender = "female" ] > 0 [
    report count elephants with [ gender = "female" ]
  ]
  [ report 0 ]
end

to-report count-males
  ifelse count elephants with [ gender = "male" ] > 0 [
    report count elephants with [ gender = "male" ]
  ]
  [ report 0 ]
end
@#$#@#$#@
GRAPHICS-WINDOW
448
19
989
561
-1
-1
13.0
1
10
1
1
1
0
1
1
1
-20
20
-20
20
0
0
1
ticks
30.0

BUTTON
12
17
79
51
NIL
setup\n
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
87
17
151
51
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
13
68
223
101
initial-number-elephants
initial-number-elephants
0
400
115.0
1
1
NIL
HORIZONTAL

SLIDER
230
68
437
101
initial-number-poacher
initial-number-poacher
0
50
20.0
1
1
NIL
HORIZONTAL

SLIDER
14
107
187
140
number-of-herds
number-of-herds
0
15
8.0
1
1
NIL
HORIZONTAL

BUTTON
163
18
227
52
NIL
go
NIL
1
T
OBSERVER
NIL
NIL
NIL
NIL
1

PLOT
1019
124
1219
274
male vs female elephants
time
number of individuals
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -2674135 true "" "plot count-males"
"pen-1" 1.0 0 -13840069 true "" "plot count-females"

SLIDER
232
106
405
139
exploration-prob
exploration-prob
0
100
14.0
1
1
%
HORIZONTAL

SLIDER
230
143
415
176
poacher-goodness
poacher-goodness
0
100
51.0
1
1
%
HORIZONTAL

CHOOSER
12
219
160
264
poacher-movement
poacher-movement
"random" "adaptive"
0

CHOOSER
14
170
202
215
law-enforcement-strategy
law-enforcement-strategy
"follow herds" "follow schedule"
1

PLOT
1022
282
1222
432
Poachers caught by zone
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"(foreach (sort zones) (sublist base-colors 0 (count zones)) [ [ z c ] ->\ncreate-temporary-plot-pen (word z) \nset-plot-pen-color c\n]\n)" "ask zones [\nset-current-plot-pen (word self)\nplot num-times-poachers-caught\n]\n"
PENS

MONITOR
1025
440
1135
485
NIL
count poachers
17
1
11

PLOT
1228
124
1428
274
plot 1
NIL
NIL
0.0
10.0
0.0
10.0
true
false
"" ""
PENS
"default" 1.0 0 -13840069 true "" "plot mean-age-females"
"pen-1" 1.0 0 -5298144 true "" "plot mean-age-males"

MONITOR
1295
348
1408
393
NIL
count elephants
17
1
11

PLOT
10
340
210
490
plot 2
NIL
NIL
0.0
10.0
0.0
10.0
true
true
"(foreach (sort zones) (sublist base-colors 0 (count zones)) [ [ z c ] ->\ncreate-temporary-plot-pen (word z) \nset-plot-pen-color c\n]\n)" "ask zones [\nset-current-plot-pen (word self)\nplot num-times-visited-by-poachers\n]\n"
PENS

SLIDER
13
268
244
301
overall-patrol-probability
overall-patrol-probability
0
1
0.35464137780638416
0.05
1
NIL
HORIZONTAL

INPUTBOX
228
376
333
436
param-line-to-use
1.0
1
0
Number

SWITCH
228
341
418
374
load-params-from-file?
load-params-from-file?
1
1
-1000

@#$#@#$#@
## WHAT IS IT?

(a general understanding of what the model is trying to show or explain)

## HOW IT WORKS

(what rules the agents use to create the overall behavior of the model)

## HOW TO USE IT

(how to use the model, including a description of each of the items in the Interface tab)

## THINGS TO NOTICE

(suggested things for the user to notice while running the model)

## THINGS TO TRY

(suggested things for the user to try to do (move sliders, switches, etc.) with the model)

## EXTENDING THE MODEL

(suggested things to add or change in the Code tab to make the model more complicated, detailed, accurate, etc.)

## NETLOGO FEATURES

(interesting or unusual features of NetLogo that the model uses, particularly in the Code tab; or where workarounds were needed for missing features)

## RELATED MODELS

(models in the NetLogo Models Library and elsewhere which are of related interest)

## CREDITS AND REFERENCES

(a reference to the model's URL on the web if it has one, as well as any other necessary credits, citations, and links)
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

mammoth
false
0
Polygon -7500403 true true 195 181 180 196 165 196 166 178 151 148 151 163 136 178 61 178 45 196 30 196 16 178 16 163 1 133 16 103 46 88 106 73 166 58 196 28 226 28 255 78 271 193 256 193 241 118 226 118 211 133
Rectangle -7500403 true true 165 195 180 225
Rectangle -7500403 true true 30 195 45 225
Rectangle -16777216 true false 165 225 180 240
Rectangle -16777216 true false 30 225 45 240
Line -16777216 false 255 90 240 90
Polygon -7500403 true true 0 165 0 135 15 135 0 165
Polygon -1 true false 224 122 234 129 242 135 260 138 272 135 287 123 289 108 283 89 276 80 267 73 276 96 277 109 269 122 254 127 240 119 229 111 225 100 214 112

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
<experiments>
  <experiment name="experiment" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="3650"/>
    <metric>mean [ age ] of elephants with [ gender = "male" ]</metric>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="scenarios A-D_varyPoachers" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count elephants</metric>
    <metric>count poachers</metric>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="9"/>
      <value value="12"/>
      <value value="15"/>
      <value value="18"/>
      <value value="21"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overall-patrol-probability">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="1 year" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="3650"/>
    <metric>count elephants</metric>
    <metric>count poachers</metric>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="experiment" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="3650"/>
    <metric>count elephants with [ gender = "female" ]</metric>
    <metric>count elephants with [ gender = "male" and age &lt; 14 ]</metric>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="zones visited" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <timeLimit steps="3650"/>
    <metric>[ num-times-visited-by-poachers ] of item 0 sort zones</metric>
    <metric>[ num-times-visited-by-poachers ] of item 1 sort zones</metric>
    <metric>[ num-times-visited-by-poachers ] of item 2 sort zones</metric>
    <metric>[ num-times-visited-by-poachers ] of item 3 sort zones</metric>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="scenarios A-D_varyElephants" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count poachers</metric>
    <metric>count elephants</metric>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="100"/>
      <value value="125"/>
      <value value="150"/>
      <value value="175"/>
      <value value="200"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overall-patrol-probability">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="scenarios A-D_varyHerds" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count poachers</metric>
    <metric>count elephants</metric>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="6"/>
      <value value="8"/>
      <value value="10"/>
      <value value="12"/>
      <value value="14"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overall-patrol-probability">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="scenarios A-D_varyHuntingEffectiveness" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count poachers</metric>
    <metric>count elephants</metric>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="30"/>
      <value value="40"/>
      <value value="50"/>
      <value value="60"/>
      <value value="70"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overall-patrol-probability">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="scenarios A-D_varyPatrollingProbabilities" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count poachers</metric>
    <metric>count elephants</metric>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exploration-prob">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
    <steppedValueSet variable="overall-patrol-probability" first="0" step="0.05" last="0.95"/>
  </experiment>
  <experiment name="scenarios A-D_varyExplorationProb" repetitions="607" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count poachers</metric>
    <metric>count elephants</metric>
    <enumeratedValueSet variable="initial-number-elephants">
      <value value="150"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="exploration-prob">
      <value value="0"/>
      <value value="5"/>
      <value value="10"/>
      <value value="15"/>
      <value value="20"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-goodness">
      <value value="50"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="initial-number-poacher">
      <value value="15"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="number-of-herds">
      <value value="10"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="overall-patrol-probability">
      <value value="0.1"/>
    </enumeratedValueSet>
  </experiment>
  <experiment name="sobol-experiment" repetitions="1" runMetricsEveryStep="false">
    <setup>setup</setup>
    <go>go</go>
    <metric>count poachers</metric>
    <metric>count elephants</metric>
    <steppedValueSet variable="param-line-to-use" first="1" step="1" last="8000"/>
    <enumeratedValueSet variable="load-params-from-file?">
      <value value="true"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="poacher-movement">
      <value value="&quot;random&quot;"/>
      <value value="&quot;adaptive&quot;"/>
    </enumeratedValueSet>
    <enumeratedValueSet variable="law-enforcement-strategy">
      <value value="&quot;follow schedule&quot;"/>
      <value value="&quot;follow herds&quot;"/>
    </enumeratedValueSet>
  </experiment>
</experiments>
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
