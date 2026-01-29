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
--
---
Let's create several typical examples, 

I also want to have a plot utils package. One thing is to render the circuit.

Final TODO:
i see you have update all path to v2, this is fine as development stage, but i want to remind you (and you should also write it down somewhere) that this "v2" should be clean up before final publish it. 

There are a lot of things we have deferre before while we were producing the first MVP. So these thing shouldn't be ignore, and should be added to TODO list in README.

We also have tried a couple of things and they should be removed after they are finalized.