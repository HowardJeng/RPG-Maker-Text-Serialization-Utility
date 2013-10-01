RPG-Maker-Text-Serialization-Utility
====================================

Ruby script to serialize unencrypted RPG Maker data files to a text format and back.

Really my only complaint about RPG Maker VX Ace is that it stores the game data all in binary so using version control with it is highly annoying. While there are scripts to convert the data to YAML for VX and XP I couldn't find one that worked with VX Ace, so I wrote my own. With a little extra work it was also possible to get the same code to work with VX and XP.

I used cygwin's ruby 1.9.3 and the Psych 2.0.0 ruby gem, which appears to be the most recent version. However, Psych 2.0.0 has some bugs that impacted the generated YAML (one major and one minor) which I monkey patched, and since I was already rewriting the Psych code, I added some functionality to make the generated YAML prettier. Long story short, this code probably won't work with any version of Psych but 2.0.0.

Basic functionality: you point the RGSS.serialize function at the directory that contains the project file and it will read the contents of the Data/ directory and dump YAML for the data files in a new YAML/ directory and the scripts in a Scripts/ directory. It can also convert save files to YAML which will be in the same directory as the project file. And, of course, it can reverse all these operations.
