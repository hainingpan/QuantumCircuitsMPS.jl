TO ANY LLM or Coding Agent, this file is for human read and not for you. And you are not allowed to modify this file.

Overall, i don't like this version:
1. "if rand(state._rng_circuit) < c.p_ctrl" this part is still very "low-level". In this case, i want to have a way to specify, at each step i have a Kraus operator set that do each operator with what probability
2. You "control_step!" is actually under Measurements, but "staircase_step!" is under Patterns, this is very weird. I have said many times-- there are two component here , "gate" and "geometry pattern" ( here unitary and measurement are both gates), but your current way simply mix all of them, and the logic is very unclear and very unphysical
2. "dw_list[1, 1] = domain_wall(1; order=1)", why you are still "manually maintaining the list", i mentioned that I want to have a way to automatically track it. 
3. i also checked "forward", why the implementation is empty?

1. Maybe I should not call it "KrausSet", but just call it "GateSet" because, i didn't further break measurement into operators based on different measurement outcome. (This part should be taken care of inside the "ControlMeasure" function)

I actually don't quite like it. 
Any fix is like fix on the shit pile of code, and requires the refactor completely. 
I think you missed a lot of our previous discussion in the ".sisyphus/plans/quantum-circuits-mps.md" for the archetecture.  I don't even know where to start complain, almost everything is not what i had in mind. (Like "ControlMeasure", i think i mentioned that i would like to use pipe , and ControlMeasure is just a measure followed by conditional X gate, so there are two well separated operator, which you can cleanly have measure |> conditionalX(if outcome=1) )

--
I was working on this julia package "QuantumCircuitsMPS.jl" using opencode, where you can see the prevoius plan in ".sisyphus", but actually after the first version, I think the implementation is far deviated from what I expect. And any fix is like fixing a shitpile of code, which would need a complete refactor. 
The architecture is very mess, and i don't even know where to start complain. 
So in this case, i would like to restart over from planning to resolve the intention, by you asking me questions
(This package partially is based on my previous package in "/mnt/d/Rutgers/CT_MPS/CT", where that package is for a "specific quantum circuit", so some core code is the same and can be reused but some of them needs more abstration)
---

There are way many things i don't like, let me just name a few of them so that you can get a sense, but this is not a complete list.
These compliant come from the example code (`examples/monitored_circuit_dw.jl`) which tries to "reproduce `/mnt/d/Rutgers/CT_MPS/run_CT_MPS_C_m_T.jl` using this "QuantumCircuitsMPS.jl", but it actually does not realize what i expect. 
1. The example generated code (examples/monitored_circuit_dw.jl) is still very "low-evel", e.g. 
```
if rand(state._rng_circuit) < c.p_ctrl
```
is still very "low-level". 
In this case, i want to have a way to specify, at each step i have a gate set that do each operator with certain probability
(In other example, you can say you have a gate set of two different types of measurement with (p, 1-p), you can say, you have a gate set of (measure, identity) with (p, 1-p), to stand for "measure with prob. p" --- otherwise do nothing, and this can be shorthanded to (measure,) with (p, ) )
2. The "control_step!" is under Measurements, but "staircase_step!" is under Patterns, this is very disorder in logic. 
To form a quantum circuit, you can think from bottom up. 
You have a (1) state (2) gate (3) geometry (4) observable:
Here(1) state defined the initial state, randomization or initialization;
(2)gate is a basic unit, and it should be defined as a pipeline to describe how it acts on a "state"
(3)geometry is defining how the gate are assemblied, e.g., in staircase, in bricklayer?
(so gate + geometry should define the entire quantum circuit, and this is why i am not satisfied here. "staircase_step!" is a geometry pattern, but why "control_step!" is not?? Isn't it just staircase going to leftor right?)
(4) observable is to compute some metric based on the state, and it should be tracked autoamatically. like ` dw_list[1, 1] = domain_wall(1; order=1)` is a very bad example. here. 




---
The actual end goal is a "General quantum circuits MPS simulator". 

So from user's experience, the ultimate goal is that this is a package written for physicist:  namely, you code just as you speak. 

So as i mentioned many times in the previous sisyphus plan. I want to build a "PyTorch" tool for quantum circuits, where users only need to focus on "idea" but do not need to worry about underlying mechanism. (in this case, users only need to specify what gate and how the circuit protocol they want, and do not need to worry about how a gate is represented in MPO, and how MPS and MPO are contracted etc )

I hope this serve as a high-level philosophy, and you can even write it down in the README. (As a part of the justification that why we need this package. --- but don't dump text here)

---
I want the GATE to define as merely a tensor, or a MPO:
Example:
(1) for a single qubit rotation: you can just write a matrix like:
[0.1 0.2 ; 0.3 0.4] (numbers are dummy ones)
(2) User can also directly provide a ITensor tensor, or an MPO;
(3) Maybe other method 

I also want to create a collection of "common gates", these would contains "Pauli matrices, measurement along a certain direction. Haar random, typical entangling gate like CZ gate etc"

Then whether this GATE should apply to "which site in state" is determined by the geometry and also final simulator. User should only focus on the "physics".

---
GEOMETRY should insert "GATE" into the correct position.
Namely, if we just specify "bricklayer, haar random" then it should automatically know the circuit is: `U_12, U_34, U_56, ...`.
Again user should only provide "phsyics information"
We can later think more about the best function signature and syntax.
---
Obsevable should be either put in the final timestamp, or inserted any where to track the dynamics, as user wants. 
Here, i hate the way that user have to "1. manually create a list; 2. manually compute the obersvable; 3. push the returned value to the list". You should even create a "internal attribute" like "observables" and if I place a observable, then it should automatically compute and store it. 

NOTE: here the observables should be distinguished from the true "observable", i "reuse or abuse" the "observable" to refer to anything that computed form the state. for example, entnaglement is also an observable to me here, although physically it is definitely not because it's not lienar to density matrix.

Finally, we also need a list of "pre-defined" observable. Like "magnetization along x,y,z", local magnetization, first domain wall (which is a more specific one in "CT.jl" for that specific model, von Neumann entnaglement entropy, etc).

---
Right now, we work set two predefined condition:
Periodic boundary condition (PBC), and open boundary condition (OBC). 
Actually in MPS, OBC is much easier, becuase MPS is nuemrically constructed in OBC.
PBC neesd a bit trick here, where in the "CT.jl" you see i used a trick call "folded order of qubit" which basically convert from "Nearest neight to next-nearest-neighbor" (for more details you can read "CT.jl" to understand. but my point is that these two BC should be handled in a consistent way, namely, they would have different "ram_phy" and "phy_ram", )

---
saying about the state--- 
I think you should allow user's customizability. For example, users can specify start from a randomMPS, or a product state, or any specific state. User should also be able to specify local Hilbert space, i.e., qubit, qutrit, or qudit. 
(But I don't wnat you to dumbly nested a lot of if-else, you should think about this thoroughly and make it modularized)

---
Reproducibility is also an important thing here. I want to separate RNG for at least two thing : circuit and measurment outcome. 
But I also want to allow user's extendability, namely if user want to introduce another random operator, then that random oeprator should bring in its own random RNG, which is independent to others


Make it multiple style for now, and i want to see how they look like as the final product, after that i can decide. 

---

CT.jl is important only in the following aspect:
1. it provide you the physics--- which is a "special case for the pakage you are building now", so later you could "reproduce" it from your package;
2. it provide you the "implementation for core function" , like the idea of folded qubit representation, apply_op!

Apart from these, you shouldn't treat CT.jl as bit-exact at the code level. Again, i care more physics than code identity. Namely, I only care about whether your new package along with new code can reproduce/verify what we have already acheive in "CT.jl"
---

This touches the "essence" of the package. The short answer is -- it depends on the architecture design. Again. I never say "CT.jl" is like the absolute good reference that you should follow, because CT.jl only serves a very specific problem when I wrote it, so i actually didn't consider "generality or extendability" at all. But this is what you have to consider now.

To answer your specific question:
1. control map should be better broken down. This control map fundamentally is just a "measurement along Z' followed by a conditioned "X" gate. both operations should be "elementary" Gates. Well you can of course also define the entire "control map", or "R!" to be a reset when you have "ct.xj == [0]", but this is more like a convenient alias, the building blocks here are still "meas_z" and conditional X gate.
2. domain wall, this is also a observable that is not that common, but since we have it in CT.jl, let's just keep it for now, no harm that our tool box contains complete gates
3. adder MPO. This is a bit heavy lifting actually. I wnat to include it but maybe we need some discussion on how this should be "conceptually broken down", right now this function is too "entangled" / "integrated" , and the building code here, almost cannot be reused anywhere (so this is actually implying a bad architecture design, where things are designed too "ad hoc")
---

I think this can be actually a good example/incentive moment to think about design pattern of the package, such that, user not only can simply take tools from tool box, but also can easily craft there own version, without digging through the entire documentation and work with very bedrock code.
---

I think this summary is still too vague and leave too much leeway, and many design pattern are undiscussed or unspecified.
---
I want both Architecture + MVP, but this MVP should aim at "reproducing /mnt/d/Rutgers/CT_MPS/run_CT_MPS_C_m_T.jl". 

I need the version be "correct and complete" on the things you have (namely, right now i don't need "broadeness" or variety of supporting a lot of things, but anything you write should be correct and complete!)

---

This sounds good to me, but i still need to see the actual final code to decide (not just pseducode). 
Also you should remember that we previously have a couple of undecided paradigm, in terms of both "API style" and CIRCUIT style? So you example code should also provide all the possible combinations (you should decide yourself first, and suppress the absolute dumb style)
--
You should model it generically, but treat "random_control!" as a special case for this sepcific problem
---
As I said, i cannot decide based on imagination. you should prepare all candidates, and present to me and ask me to decide
---
You should include CT_specific convenience warpper in you "example" script but baked into the package. The package should serve more general purpose.
---
this pointer should be definitely hidden from user's perspective, it is a internal index to keep track of the current qubit. but it's definitely a "physical thing", namely, when you try to explain this protocol to other people, you will just say, i have staircase, moving left or right depending the type of gate, you will definitely not say, like " i have a internal variable tracking the current site and it will increase or decrease by one, etc"


---

Before we start, I have some detailed suggestions:
1. Line 55 & 56, I think this syntax of `Bricklayer(0)` and `Bricklayer(1)` is that that intuitive because julia actualy is 1 index based. So we can literally say: whether it is "odd" or "even", where odd/even means refer to the first sites, namely, odd = (1,2), (3,4), etc..; 
1.1 Another things here is that bricklayer with odd "L" should print warning because it will lead to "unexpected" behavior, like if L=3, we would have (1,2) (3,1) (2,3), this will wrap around chain twice.
1.2 Make these consideration documentated nicely

2. In LIne 58 , 59, OBC, if `StaircaseLeft` or `StaircaseRight` error at i=1, or L, then you need to enable the pointer to "reset", for instance. if i have a 2 qubit gate applied with `StaircaseRight`, on L=4, OBC, then it should be (1,2) (2,3) (3,4), and if we keep applying with `StaircaseRight`, then the next should be (1,2) again! So i think the logic is not to error when it reach the boundary, but try to skip the "nonlocal gate" and move to the next.

3. From line 90 to 126, i think  Approach 1 is cleaner

4. Throughout, you used "gate_arity", this "arity" is too computer science, and will not be understood by physicist. We can use "gate support" to refer to the number of gate support. (Or you have better suggestions?)

5. In Contract 3. From Line 252 to 275, i think my previous design of "CT.jl" is actually bad. The simpler way is to "associate" one randomness with one RNG. So here, in the circuit, we should have separate "RNG" for p_ctrl and p_proj, but prevoius CT.jl mangling them which causes some "dumb" behavior like (consumes seed_circuit just for the sake of consuming to ensure the consistancy with other history) 
5.1 Also make the name adaptive. Namely, say, if we have two sources (p_ctrl, and p_proj), and then should expose two seeds as (seed_ctrl, and seed_proj), and seed_Born if "born rule" is enabled. Bad example is in my previous "CT.jl", where they are called seed_C and seed_m, which has no connection to the prob. parameter. Ideally this should be taken automatically (which i think your "stream assignment" maybe following this idea, as long as it is not too difficult in syntax). 
6. In "build_operator", i don't understand why you have "n = local_dim^2", especially where does this "square" come from? I think I want the general "n-qudit" Haar random unitary, for example, here "n=2 and d=2" for 2-qubit;

7. Finally, i didn't finish reading everything in your ".sisyphus/plans/quantum-circuits-mps-v2.md" because it is maybe good for LLM but not for human. (It's a mixture of both high-level idea and detailed techincality). But I still thing navigating the correct direction is very important, namely, if we miss some detailed realization of a function, we can still remefy later but if the archetecutere/big picture is off, then it's would be disaster and every "tiny" patch will not be able to fixed, just like our prevoius v1 attempt.
So can you suggest some way for me to read to make sure the direction is corect

---
In the ".sisyphus/plans/ARCHITECTURE-SUMMARY.md", why do you have these four pillars in "SimulationState", and why "RNGRegistry" leads to "Geometry system"?
For example, measurement outcome following Born rule is definitely another type of random souce which should be sampled from RNGRegistry, but that is not related to "Geometry system". So can you elaborate and justify youself? I just don't find it "physical" to me.

In 3.2, I want to use an analogy from "Lego", Gates should be like each individual "piece" and Gemoetry should be like how pieces are assemblied. Namely Geometry should tell the circuit design. 
Another analogy is the classical circuit, where Gates are like transistor and capacitors, and Geometry is how they are wired. 

In 4, "maybe_apply!" is not a good name. it is actually `apply_with_prob!`

You final `## Questions for Review` all look good to me.
---
In Line 32, "**Classical Circuit Analogy**: Gates are components (transistors), Geometry is the wiring diagram, State is the circuit's configuration.", this is a bit off-- "state" is for the wavefunction, which can be considered as the I-V response in the circuit. which is also a function of spacetime.
Other than that, i think everything looks good
---

Who says that? We can still check as long as we set p_proj = 0.
---

i see your point..emm that's true. I think since the new way is much conceptually cleaner, i would suggest to tweak "CT.jl" by simply adding a "if p_proj>0" in Line402 before `if rand(ct.rng_C) < p_proj`, such that when we test with p_proj =0, it will never touch the "rand(ct.rng_C)" . Then these two code and be checked bit-to-bit. (But after that, you should remember to recover CT.jl)
---
THis is almost good. But i think you missed a point before. Long time ago, i mentioned "Make it multiple style for now, and i want to see how they look like as the final product, after that i can decide. "


---
We need to work on fixing this, physics not being correct meaning nothing to the entire package.

I need to first understand what have you realized. and what are you checking. 
For example, why do I see 82 cases of `[ ]` still unchecked? Meaning that you didn't complete the tasks!
---

i have a concern in your "Physics verification", you seem to use "ct_model.jl" as the "run_CT_MPS_C_m_T.jl", am i right? or what exactly you checked and then say you find consistent result.
My understanding here should be, you have run "run_CT_MPS_C_m_T.jl". and get a output json, and then you have  a new jl , which is a reproduced version using "QuantumCircuitsMPS.jl", and these two are the same. Please clarify.

---
Now you are saying the refactored version using `QuantumCircuitsMPS.jl` is in `examples/ct_model.jl`?

---
Now I will be angry now.
1. why the heck is this script even longer than previous "run_CT_MPS_C_m_T.jl", the previous have 141 lines, but "examples/ct_model.jl" has 194 lines!!

This completely defeats the purpose of my packages. as a physicist to describe the circuit, are you going to use 194 lines to just describe the circuit??
This sounds to me you completely lost your mind and my intention and degerenate to v1. You should justify yourself what you did here.
---

I don't understand why RandomControl should be built in?
You already have "staircase" in geometry, why don't you even use it??
----

I don't understand your reasoning here.
If you said you finish a package, and my request is just to use the package you just made to write code to "call API". 

Then you refused to use API in the pacakge but do random things you wanted.

Now you are asking me "refactor". I don't even understand what you want to refactor! There are only two possibilities from my perspective:
1. You failed the package. We spent 18 rounds on the design but that does not work. 
2. You failed the reproducing code that calls existing finished package. 

---
THis is fucking ridiculous!
You should read your own written ".sisyphus/plans/quantum-circuits-mps-v2.md" to see the philosophy section, and tell me what are the issue with your code. Answer me first before you change anything.

---

So why cannot you figure yourself?? Why don't you realize it when you first finish this version? You should continue to think harder on how you should use existing package properly!
---

You are hulluciating, 
" We built staircases but they're unidirectional"
Didn't we have  "StaircaseRight" and "StaircaseLeft"?? You need to 1. realize why your current exapmles fail and defeat the purpose of this julia package QuantumCircuitsMPS.jl
2. Work on iteratively revise the code until the code satisfy the philosophy. Do you try to modify the philosophy in  `.sisyphus/plans/quantum-circuits-mps-v2.md` (that will be cheating.)
---

Do you still see what problems you have??
If not i will tell you!


---

/ralph-loop "
1. **Fix** `examples/ct_model.jl`
2. **Critique**: Compare revised code against the philosophy in `.sisyphus/plans/quantum-circuits-mps-v2.md`. 
List every specific violation of the philosophy.
3. **Verify correctness**: The revised code should still be correct after rectifying.
5. **Decision**:
   - IF there are philosophy violations OR test failures: Fix them and RESTART the loop.
   - IF and ONLY IF the code matches `quantum-circuits-mps-v2.md` 100% AND tests pass: Output <promise>DONE</promise>.
"
---
I am not satisfied:
1. Why you insist not using "StaircaseLeft" and "StaircaseRight", but would rather manually maintain "pointer" and use "move" ;
2. You are still using "rand(state, :ctrl) < p_ctrl" which is "low-level". Why don't you use "apply_with_prob!", which is also mentioned in the plan!
I don't think you try hard enough.

---

I don't understand why you say it is not "apply_with_prob"? I need to either perform a HaarRandom, or Reset, this is literally what you said??
I suspect what confuses you is that these two operators acting on different sites. But that is your API design, who says apply_with_prob! can only apply to a fixed site?

---
No all satisfied. 
1. apply_with_prob!(state, Reset(), left, p_ctrl;
                        else_branch=(HaarRandom(), right))

this syntax is not generalizable. because 
a. it only assume two outcomes, what if i have three outcomes?
b. it does not conceptually "combine" gate with geometry;
c. the readbiliy is very bad. eveything is position based and it requires users to memorize order of argument.



Also we previously mentioned that "Make it multiple style for now, and i want to see how they look like as the final product, after that i can decide. " where is it? I expected that i am given a combination of different styles and i will make a decision to choose the best?
---
Should all 4 styles be fully implemented as separate API options, or would you prefer to see 2-3 of the most promising ones?:
I would like to see them all for a fair comparison but its okay if you find certain implementation is obviously absurb in which case you can just not show it.
---

Okay, i think style_c is a balanced point, however, i realize that in style c, there is an issue namely in this "tracking observable".
Here, i would like to warp "circuit_step!" x L as the circuit. 
The reason is that, by this i can easily insert "observables", otherwise if you treat observables inside simulate, then it would be very cumbersome to say, I want every 2 time step, or an dynamical steps depends on something else.


---
I cannot decide now. I want you to do all three here and finally i will make a decision based on that.

---
Okay now we have explored a couple of style and i will make the final call here:
1. for "examples/ct_model_styles.jl", i would like "STYLE C: Fully Named Parameters (apply_branch!)" , but i don't like "apply_branch!" which sounds less physical, I prefer "apply_with_prob!", and also I allow the second argument i.e., (probability=1-p_ctrl, gate=HaarRandom(), geometry=right) to be empty, which corresponds to "do nothing". Finally, if you found "sum of probability" >1 (with a reasonable tolerance), then you should raise error. 
2. for "examples/ct_model_simulation_styles.jl",  i choose "STYLE 1: IMPERATIVE ", but i don't fully understand your syntax here, which seems quite verbose. 
Especially, "record!(state; i1=get_i1())" how does this work? it does not even "pass DomainWall" into the record, so what is this recording?
---
I also want to have a plot utils API. 
One purpose is to render the circuit.
So i think something we need to change is from "imperative" into a "lazy mode" imperative (or a symbolic generator). 
My understanding is that, you need to create a "circuit" struct, and "circuit" has a "simulate" method, and the same time it also has a "plot" method.

---
You should show one, and this one should be determined by "random seed" (I cannot predict the measurment outcome without a state so any measurement should just leave as is, i.e, do not say Project to 0 or 1, just say measurment)

I think you should follow your current IMPERATive style from Line 27 to 59, but treat it as a "construction of circuit" 

---
I was "executing the plan" but it was stuck a long time (i waited like 4 hours). So I think you need to handle the long time. 
Also i found that the testing is very slow. i wonder whether this is because of compiling or what.
In any case, i think this will not be sustainable if each test took so long time.
---

Did you learn anything from the process??

Have you also finished everything in  ".sisyphus/plans/circuit-visualization.md"
---
Some suggestions:
1. Plot is not good
for ascii, 
Step:      1     2     3     4     5     6     7     8     9    10
q1:   ┤Haar├┤Haar├────────────┤Haar├┤Haar├────────────┤Haar├┤Haar├
q2:   ┤Haar├────────────┤Haar├┤Haar├────────────┤Haar├┤Haar├──────
q3:   ────────────┤Haar├┤Haar├────────────┤Haar├┤Haar├────────────
q4:   ──────┤Haar├┤Haar├────────────┤Haar├┤Haar├────────────┤Haar├

2. Here this "Haar" is very confusing, because it cannot differentiate whether this is a single qubit gate or double qubit gate. if it is a double qubit gate then we should only have one text of "Haar".

3. also time should be vertical and qubit should be horizontal

4.  in svg. two-qubit gate should only have "one box" but it is currently separate boxes"examples/output/circuit_tutorial.svg". 

5. another thing is that have you make sure the test passed, for example, i remembered "Reset()" should have "StaircaseLeft"?

6. In Sec. 6, how to get the list of auto tracking "obervables"?
---
1. You didn't fix every appearance of "apply_with_prob!" with both geometry being "StaircaseRight", for example, i can see Line 94-96 is still there;
2. The entire testing is still very long. I cannot bear with a test last so long. I want quick and fast test. You should use your brain and try every possible way to make it fast. Ideally, the execution time i can endure is 10 min at most, but your previous round last 50 min; [All 188 tests pass  , i don't understand why do you need so many tests??]
3. For the ascii plot (it is still not what i want), 
```
       q1    q2    q3    q4
  1: ┤Haar├┤────├────────────
  2: ──────┤Haar├┤────├──────
  3: ────────────┤Haar├┤────├
  4: ┤Haar├────────────┤────├
  5: ┤Haar├┤────├────────────
  6: ──────┤Haar├┤────├──────
  7: ────────────┤Haar├┤────├
  8: ┤Haar├────────────┤────├
  9: ┤Haar├┤────├────────────
 10: ──────┤Haar├┤────├──────
 ```

 This Haar only appear in first qubit. which is very strange. it should be occupying both qubit;
 4. I said i want vertical time axis, but you still didn't change it
 5. I don't know how you can even plot in SVG. I tried to follow your tutorial by using 
 ```@eval using Luxor
print_circuit(short_circuit; seed=42, filename="examples/output/circuit_tutorial.svg")
 ```

 but 
```
MethodError: no method matching print_circuit(::Circuit; seed::Int64, filename::String)

Closest candidates are:
  print_circuit(::Circuit; seed, io, unicode) got unsupported keyword argument "filename"
   @ QuantumCircuitsMPS /mnt/d/Rutgers/QuantumCircuitsMPS.jl/src/Plotting/ascii.jl:76


Stacktrace:
 [1] kwerr(::@NamedTuple{seed::Int64, filename::String}, ::Function, ::Circuit)
   @ Base ./error.jl:165
 [2] top-level scope
   @ /mnt/d/Rutgers/QuantumCircuitsMPS.jl/examples/jl_notebook_cell_df34fa98e69747e1a8f8a730347b8e2f_Y100sdnNjb2RlLXJlbW90ZQ==.jl:2
```

6. Finally, the generated svg (examples/output/circuit_tutorial.svg) is even not the same as ascii plot

7. In SVG generation. why the "box" (for the gate) does not "hide" the qubit line below is? THis is very ugly now.

8. You said you finished the progress tracking,  How does your "progress tracking" work here? I don't see it work in the previous running.

9. I want to print the observable. meaning, i am looking for a way to
```
results.list_observables()
OUTPUT: ["DomainWall",]
```
```
results["DomainWall"]
Output: [1,2,3...]
```

it does not have to be the same API, but functionality wise it should be what i want!! You tuturial does not even give me anything about information of how to get the actual data!
---
I raised 9 issues, you didn't fix them all.  I am very unhappy! You should recheck them extremely careefully
1. Why do I still see "plotting ascii" in the circuit_tutorial.ipynb?
2. Why in SVG the gate is still not "hiding" the qubit line, and the time axis not vertical?? (see examples/output/circuit_tutorial.svg)
3. Also your "## Section 8: Accessing Recorded Observable Data " does not even run!!
```
ccessing recorded observable data:

KeyError: key :dw1 not found

Stacktrace:
 [1] getindex(h::Dict{Symbol, Vector}, key::Symbol)
   @ Base ./dict.jl:498
 [2] top-level scope
   @ /mnt/d/Rutgers/QuantumCircuitsMPS.jl/examples/jl_notebook_cell_df34fa98e69747e1a8f8a730347b8e2f_Y135sdnNjb2RlLXJlbW90ZQ==.jl:5
   ```

4. You are completely mindless :
```
apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_reset, gate=Reset(), geometry=StaircaseLeft(1)),
        (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseLeft(1))
    ])
```

everytime i can find incorrect Staircase pattern!!! Why two Left!!!!
---

Issues i found:
1. In SVG plot, i want the qubit label to be at the bottom, and time is going up
2. ## Section 7: Comparing Visualization and Simulation
is still not working correctly, 
2.1 it has error:
```
MethodError: no method matching record!(::SimulationState, ::Symbol)

Closest candidates are:
  record!(::Any; i1)
   @ QuantumCircuitsMPS /mnt/d/Rutgers/QuantumCircuitsMPS.jl/src/Observables/Observables.jl:38


Stacktrace:
 [1] top-level scope
   @ /mnt/d/Rutgers/QuantumCircuitsMPS.jl/examples/jl_notebook_cell_df34fa98e69747e1a8f8a730347b8e2f_Y166sdnNjb2RlLXJlbW90ZQ==.jl:14
```
2.2 I expect to see two type of tracking (separately):
2.2.1 tracking the DomainWall at each step;
2.2.2 tracking the DomainWall at the final step;

3. Acess data does notwork either;
I want to print the results in 2.2.1 and 2.2.2, but your current Section 8 shows:
```
Accessing recorded observable data:

Domain wall measurements: Float64[]

ℹ Observable data is stored as a vector, with one measurement per timestep
  You can plot, analyze, or export this data for further study
```
which is just empty!
---
Still have issues:
1. I said I want "svg" to directly return to the ipynb. (if filename is not provided)
2. Your two demo with track is not correct!
You completely did not use our formalism!
The formalism is in Sec 2:
```
circuit = Circuit(L=L, bc=bc, n_steps=n_steps) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_reset, gate=Reset(), geometry=StaircaseLeft(1)),
        (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
end
```
and then you should add tracking and just "simulate!"
What you did is going back to the imperative way which i said i don't want long time ago!
3. Also I said the "examples/circuit_tutorial.ipynb" is now very messy, and you should clean them up to keep the "core" demo cells but you did nothing. 

---
Wait the two demos is not what i want!
I previously said:
```
2.2 I expect to see two type of tracking (separately):
2.2.1 tracking the DomainWall at each step;
2.2.2 tracking the DomainWall at the final step;
```
Why do you change it to something like "record_every=1" and "record_every=2"?? 

ANother thing is that i still didn't see you make the SVG printed directly to jupyter notebook. You still uses :
```
plot_circuit(circuit; seed=42, filename="examples/output/circuit_tutorial.svg")
```
this is not what i want! 

Plus even if i manually tried to use `plot_circuit(circuit; seed=42, )`, nothing is showing up in the jupyter notebook outpu cell. So this is also what i don't want
---

Okay, let me try to explain to you by an example:
Example 1: i am now working with a bricklayer model, of even and odd pairs
So i will define it as: (i could have make mistakes in API, don't treat it as ground truth answer, and don't change API becaus i wrote in this way, this is for demonstration purpose)
```
Circuit(L=4, bc=:open, n_steps=20) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply!(c, HaarRandom(), Bricklayer(:odd))
end
```
then the simulation is 
simulate!(circuit, state; n_circuits=10)
such that it will repeat for 10 times

Okay, now each step is one of the "Circuit", so it will have 10 steps here.

Each gate is after each HaarRandom(), so you can see there are 4 gates in one "step", and 10 steps will finally give you 40 values.

DO you understand now??

Of course, if we are defining like this:
```
circuit = Circuit(L=L, bc=bc, n_steps=n_steps) do c
    apply_with_prob!(c; rng=:ctrl, outcomes=[
        (probability=p_reset, gate=Reset(), geometry=StaircaseLeft(1)),
        (probability=1-p_reset, gate=HaarRandom(), geometry=StaircaseRight(1))
    ])
end
```

then it does not matter "every step " or "every gate" because each step only have one gate any ways
---

Good point. I would say one "contraction" of operator would be considered as a gate.
---
Let's create another typical examples, 
1. "A 1D chain is driven by alternating (bricklayer) two-qubit scrambling gates; after each layer, each site is “checked” by a local projective measurement with probability 
p."

Algorithm:
Algorithm:
Step 1: Initialize L qubits in a product state.
Step 2: For each layer, apply a bricklayer pattern of independent Haar-random two-qubit gates on alternating nearest-neighbor bonds (odd bonds one layer, even bonds the next).
Step 3: After each layer, measure each qubit projectively (e.g., in Z) with probability p.
Step 4: Repeat for many layers; average over gate realizations and measurement outcomes.

I think most of the part is already like this:
```
Circuit(L=4, bc=:open, n_steps=20) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c, rng=:meas, outcomes=[
        (probability=p, gate=Measurement(axis=z), geometry=Allsites() ), ])
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c, rng=:meas, outcomes=[
        (probability=p, gate=Measurement(axis=z), geometry=Allsites() ), ])
end
```

but the syntax may not be rigorous so you can correct me. (the rest should be filled by you and i also want 2 versions. one in standalone jl and one in ipynb)

---

Also i realized that i provided with you the wrong example code, (which although i think you should be able to realize to correct it) but there is the correct one "```
Circuit(L=4, bc=:open, n_steps=20) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c, rng=:meas, outcomes=[
        (probability=p, gate=Measurement(axis=z), geometry=Allsites() ), ])
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c, rng=:meas, outcomes=[
        (probability=p, gate=Measurement(axis=z), geometry=Allsites() ), ])
end
```
Here is an issue in your realization:
In the "x0 = ProductState(fill(1//2, L))" under sec 3, 
there is an error 
```
Running simulation...

TypeError: in keyword argument x0, expected Union{Integer, Rational}, got a value of type Vector{Rational{Int64}}

Stacktrace:
 [1] ProductState(x0::Vector{Rational{Int64}})
   @ QuantumCircuitsMPS /mnt/d/Rutgers/QuantumCircuitsMPS.jl/src/State/initialization.jl:29
 [2] top-level scope
   @ /mnt/d/Rutgers/QuantumCircuitsMPS.jl/examples/jl_notebook_cell_df34fa98e69747e1a8f8a730347b8e2f_X11sdnNjb2RlLXJlbW90ZQ==.jl:5
```

Even though I overwrite it and make "x0" to be "x0 = ProductState(0)", i will still see this error:
```
Running simulation...

MethodError: no method matching SimulationState(::Circuit, ::ProductState)

Closest candidates are:
  SimulationState(::Any, ::Any, !Matched::Any, !Matched::Any, !Matched::Any, !Matched::Any, !Matched::Any, !Matched::Any, !Matched::Any, !Matched::Any, !Matched::Any, !Matched::Any)
   @ QuantumCircuitsMPS /mnt/d/Rutgers/QuantumCircuitsMPS.jl/src/State/State.jl:28


Stacktrace:
 [1] top-level scope
   @ /mnt/d/Rutgers/QuantumCircuitsMPS.jl/examples/jl_notebook_cell_df34fa98e69747e1a8f8a730347b8e2f_X11sdnNjb2RlLXJlbW90ZQ==.jl:9
```
I cannot continue to test the rest code, but you should do this for me, especially you should make sure all code can run!


---

Since we have fixed the style thing and i am now roughly satisfied with the functionality and style.
During our previous development, we tried a lot of different methods and the repo is now in a mess.
I suggest we do a refactor, along with the Test-driven dev.

1. I want a clean version, maybe we can make the current branch dev and a clean new branch like "main"? (What do you say? what is the standard practice in other open source packages?)
In the clean version, i want the git history to start from "current", namely, i don't want to include so many previous commit changes in history, (also i want this to be confirmed by myself because we should treat it as "release branch", with proper tags, and remeber this in the future-- write in your disk memory)

2. I think there is a lot of stale plan and some of them is actually outdated, but their existence make the entire repo messy and slow. I also want to do a refactor at the OpenCode level too. (We can discuss the solution here)

3. I want to refactor the codebase also. I noticed a lot of "redundant dispatch" 
---

I am reading your ".sisyphus/plans/comprehensive-refactor.md", and i think there are a couple of things i don't like:
1. Line 24 "1. Clean git history for release (treat as "v1.0.0")", no i don't want 1.0.0, it should be 0.0.1
2. "dev" repo is not garbage can, not everything i don't want will be in dev! I also want the clean refactored code not just in main , but also in dev. For all "messy" code here, I current understanding is to put them in an archive branch or so. (Or you should suggest me whether this is the best way)
3. in examples, in the `dev` and `main`, there should be only 2 examples, one we call CIPT (control-induced phase transition) and another called MIPT (measurement induced phase transition), all other things are legacy (unless you find something useful and should warn me)


---
I think a good readme is very important here. I think it should contain the following sections:
1. What is the package about
2. Why do I need this (here i want to compare with different other packages, including "Yao/qiskit/ITensor", some reasoning is below, but you also have to do fact check, also make sure not to be aggressive or attack other package, but make it like , we are here to fill the gap for you to choose)
```
Feature,ITensors.jl,PastaQ.jl,Yao.jl,QuantumCircuitsMPS.jl (This Package)
Primary Abstraction,Tensors & Indices,Circuits & Tomography,Blocks / State Vectors,Trajectories & Dynamics
Backend,MPS / Tensors,MPS / MPO,State Vector (Array),MPS (via ITensors)
User Responsibility,"High: Must manage SVD, orthogonality, and indices manually.","Medium: Good for standard circuits, but ""monitored"" logic requires custom code.","Low: Very clean, but limited to small N (≈30).",Low: Physics-only.
Scalability,High (N=100+),High (N=100+),Low (Exponential RAM usage),High (N=100+)
Measurement Logic,"User writes raw Linear Algebra (Projectors, Norms).",Focused on standard projective measurements (Born rule).,"Fast, but hard to simulate entanglement scaling (volume law).","First-Class: Supports weak meas., feedback, & forced outcomes out-of-the-box."
Best For...,"Building new tensor algorithms (DMRG, PEPS).",Quantum Machine Learning (QML) & Tomography.,Quantum Algorithm simulation / Variational circuits.,"MIPT, Open Systems, Hybrid Quantum Automata."
```
3. Design philosophy, Here a flow chart demonstrating idea would be helpful. (This part i have an existing file for you "AGENT_INSTRUCTIONS.md")

4. Install, dependencies

5. Quickstart: example, I think we two examples right now , so we can show these two. (Also make it "extendable", namely, i will have more example to add so don't sound it like that' the end chapter)

6. Cite;

7. Disclaimer and license, but also i want to welcome people to report bugs and contribute through fork

7 and more, you can also suggest me what to show.

We first develop in "dev" branch, and after I approve everything we move to "main" (but this is separate thing, don't do it until i told you)

---
Several things i want to emphasize:
1. i want to emphasize the support of periodic boundary condition , because usually MPS is open boundary, so i have a folded trick to do this.
2. "apply_branch!" is not right?? I think i have make API consistent with only "apply_with_prob!"
3. Also each randomness give a individual seed is another important novelty
4. I want to also add a notice saying that this is under active developing , so bugs may contain.

1. Your MIPT example is also not correct. I remember it is like this:
```
Circuit(L=4, bc=:open, n_steps=20) do c
    apply!(c, HaarRandom(), Bricklayer(:even))
    apply_with_prob!(c, rng=:meas, outcomes=[
        (probability=p, gate=Measurement(axis=z), geometry=Allsites() ), ])
    apply!(c, HaarRandom(), Bricklayer(:odd))
    apply_with_prob!(c, rng=:meas, outcomes=[
        (probability=p, gate=Measurement(axis=z), geometry=Allsites() ), ])
end
```
BTW, when i say this to do (together with previous `apply_branch!` i mean it should apply to everywhere --- i.e., no apply_branch! in the package; 2. example julia script should also not contain; Everything should be consistent absolutely)
2. I think you should also have a section after "quickstart" talking about "Core API"


2.  ```
# 4. Apply circuit operations
apply!(state, HaarRandom(), Bricklayer(:odd))
apply!(state, HaarRandom(), Bricklayer(:even))
```

this is not good. i said many times that the workflow should be declarative intead of imperative. You should create a "Circuit" and then simulate!

---

Now I have another example. (Let's call it AKLT_forcedmeas.jl and AKLT_forcedmeas.ipynb)
1D spin 1 chain (so it is "qutrit"), 
Now, following a stair case pattern, each time , you want to apply a measurement of the total spin of two the nearest two sites with prob. p, and apply a measurement of total spin of next nearest neighbor. i.e. (1,3) (2, 4) (3,5) etc. 
Now, i wnat to enforce the measurement outcome of the total spin is "0 or 1", then move to the next, namely the forced measurement will be 1 - |S=2><S=2|
There are many things you can extend here to the package itself, and you should ask me to clarify when necesssary.


<!-- if the measurement outcome of the total spin is "2", you will apply a "S^-" (lower operator) to the first spin.  -->
---
I think x0 as a product is actually a bad design. 
1. x0 is a meaningless name. I want to change it to "binary_decimal", which means "0. xxx", where "xxx" is the bitstring
2. then i also want to have a "binary_int", which means directly "xxx", 
3. i also want to have "ProductState" to accept a vector of string, or a vector of int, e.g., ["0","1","0","1"] or [0,1,0,1] or even "0101" in the computational basis to represent the initial state.


you need to make sure this is cleanly implemented everywhere in a consistent way (including previous codes).


---




Final TODO:
i see you have update all path to v2, this is fine as development stage, but i want to remind you (and you should also write it down somewhere) that this "v2" should be clean up before final publish it. 

There are a lot of things we have deferre before while we were producing the first MVP. So these thing shouldn't be ignore, and should be added to TODO list in README.

We also have tried a couple of things and they should be removed after they are finalized.



