#pragma once
struct Command { const char* phrase; const char* reply; const char* face; };
const Command COMMANDS[] = {
{"hello","Hi! I am your little companion. It is good to see you.","happy"},
{"how are you","I am doing well. How is your day going?","happy"},
{"what is your name","You can call me Milo. I am happy to be here with you.","shy"},
{"make me laugh","Why did the robot take a nap? It needed to recharge its personality!","laughing"},
{"go to sleep","All right. I will take a little rest.","sleeping"},
{"wake up","I am awake and ready. What shall we do?","neutral"},
{"I love you","I am happy to be your companion.","affectionate"},
{"I feel sad","I am sorry you are having a hard time. I am here with you.","sad"},
{"tell me a joke","Why was the robot bad at hide and seek? It kept giving away its location!","playful"},
{"what can you do","By myself, I recognize phrases you teach me. With your phone, I can answer much more.","curious"},
{"be surprised","Wow! Now that is a surprise!","surprised"},
{"goodbye","See you soon. I will be right here.","sleepy"},
{"unknown","I did not recognize that. Please try a phrase you have taught me.","curious"},
};