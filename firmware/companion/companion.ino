#include <Arduino.h>
#include <SPI.h>
#include <SPIFFS.h>
#include <Preferences.h>
#include <ESP_I2S.h>
#include "recognizer.h"
#include "commands.h"
#include "replies.h"

constexpr int COMMAND_COUNT=12, EXAMPLES=3;
Speech::Features (*templates)[EXAMPLES]=nullptr;
Speech::Features current;
uint8_t counts[COMMAND_COUNT]={0};
int16_t* pcm=nullptr;
String face="neutral";
bool hardwareAudio=false, storageReady=false;
I2SClass mic, speaker;
float rejection=1.6f; // Provisional threshold; real speaker validation is required.
Preferences prefs;
#include "phone_link.h"

void lcdOff(){
  // Waveshare ESP32-S3-LCD-1.47, NON-B. Backlight is active high GPIO48.
  digitalWrite(48,LOW);pinMode(48,OUTPUT);digitalWrite(48,LOW);
  pinMode(39,OUTPUT);digitalWrite(39,LOW); // hold ST7789 reset; no panel init or white flash
  pinMode(42,OUTPUT);digitalWrite(42,HIGH);
}
void status(){
  Serial.printf("{\"ok\":true,\"firmware\":\"little-companion-1.0\",\"chip\":\"ESP32-S3\",\"psram\":%u,\"heap\":%u,\"lcd\":\"off\",\"face\":\"%s\",\"hardware_audio\":%s,\"storage\":%s,\"threshold\":%.3f,\"trained\":[",ESP.getPsramSize(),ESP.getFreeHeap(),face.c_str(),hardwareAudio?"true":"false",storageReady?"true":"false",rejection);
  for(int i=0;i<COMMAND_COUNT;i++)Serial.printf("%s%d",i?",":"",counts[i]);Serial.println("]}");
}
void reply(int id,bool usb=true){
  if(id<0||id>COMMAND_COUNT)id=COMMAND_COUNT;
  face=COMMANDS[id].face;
  auto& audio=REPLIES[id];
  if(usb){
    Serial.printf("{\"ok\":true,\"id\":%d,\"face\":\"%s\",\"text\":\"%s\",\"audio_bytes\":%u}\n",id,COMMANDS[id].face,COMMANDS[id].reply,audio.size);
    Serial.write(audio.data,audio.size);Serial.flush();
  }
  if(hardwareAudio){speaker.write((uint8_t*)audio.data+44,audio.size-44);}
}
void recognize(bool usb=true){
  float best=1e9,second=1e9;int found=-1;
  int categories=0;
  for(int c=0;c<COMMAND_COUNT;c++){
    if(!counts[c])continue;categories++;
    float score=1e9;
    for(int s=0;s<counts[c];s++)score=std::min(score,Speech::distance(current,templates[c][s]));
    if(score<best){second=best;best=score;found=c;}else second=std::min(second,score);
  }
  // At least two commands and two recordings per selected command required.
  if(categories<2||found<0||counts[found]<2||best>rejection||best>second*.87f)found=COMMAND_COUNT;
  if(!usb&&phoneRecognized(found))return;
  reply(found,usb);
}
String pathFor(int id,int sample){return "/en_t"+String(id)+"_"+String(sample)+".bin";}
void load(){
  for(int c=0;c<COMMAND_COUNT;c++)for(int s=0;s<EXAMPLES;s++){
    File f=SPIFFS.open(pathFor(c,s));if(!f)break;
    Speech::Features temp;
    if(f.size()!=sizeof(temp)||f.read((uint8_t*)&temp,sizeof(temp))!=sizeof(temp)||temp.frames<1||temp.frames>Speech::MAX_FRAMES)break;
    bool valid=true;for(int i=0;i<temp.frames;i++)for(int d=0;d<Speech::D;d++)if(!isfinite(temp.v[i][d]))valid=false;
    if(!valid)break;templates[c][s]=temp;counts[c]++;
  }
}
void handle(String line){
  line.trim();
  if(line=="STATUS"){status();return;}
  if(line.startsWith("PHONE ")){phoneUSBMirror=true;phoneHandleJSON(line.substring(6));phoneUSBMirror=false;return;}
  if(line=="RESTART"){Serial.println("{\"ok\":true}");Serial.flush();delay(100);ESP.restart();return;}
  if(line=="FORMAT TRAINING"){
    SPIFFS.end();bool formatted=SPIFFS.format();storageReady=formatted&&SPIFFS.begin(false);
    if(storageReady)memset(counts,0,sizeof(counts));status();return;
  }
  if(line.startsWith("SAY ")){reply(line.substring(4).toInt());return;}
  if(line.startsWith("FACE ")){
    String requested=line.substring(5);bool valid=false;
    const char* names[]={"neutral","happy","laughing","shy","curious","surprised","sleepy","sleeping","affectionate","playful","sad","listening","thinking","speaking"};
    for(auto name:names)if(requested==name)valid=true;
    if(!valid){Serial.println("{\"ok\":false,\"error\":\"invalid_face\"}");return;}
    face=requested;status();return;
  }
  if(line.startsWith("THRESHOLD ")){float x=line.substring(10).toFloat();if(x>=.1f&&x<=4)rejection=x;status();return;}
  if(line.startsWith("CLEAR ")){
    int id=line.substring(6).toInt();if(id>=0&&id<COMMAND_COUNT){for(int s=0;s<EXAMPLES;s++)SPIFFS.remove(pathFor(id,s));counts[id]=0;}status();return;
  }
  if(line=="HARDWARE ON"){
    if(hardwareAudio){status();return;}
    mic.end();speaker.end();
    mic.setPins(4,5,-1,6);speaker.setPins(7,8,9,-1);
    bool rx=mic.begin(I2S_MODE_STD,16000,I2S_DATA_BIT_WIDTH_32BIT,I2S_SLOT_MODE_MONO,I2S_STD_SLOT_LEFT);
    bool tx=speaker.begin(I2S_MODE_STD,16000,I2S_DATA_BIT_WIDTH_16BIT,I2S_SLOT_MODE_MONO);
    hardwareAudio=rx&&tx;prefs.putBool("hardware",hardwareAudio);status();return;
  }
  if(line=="HARDWARE OFF"){hardwareAudio=false;mic.end();speaker.end();prefs.putBool("hardware",false);status();return;}
  if(line.startsWith("AUDIO ")){
    char mode[12];int id=0,bytes=0;
    if(sscanf(line.c_str(),"AUDIO %11s %d %d",mode,&id,&bytes)!=3||bytes<6400||bytes>128000||bytes%2||!pcm||!templates){Serial.println("{\"ok\":false,\"error\":\"invalid_audio_header\"}");return;}
    Serial.println("{\"ready\":true}");
    Serial.setTimeout(10000);size_t got=Serial.readBytes((char*)pcm,bytes);Serial.setTimeout(1000);
    if(got!=bytes){Serial.println("{\"ok\":false,\"error\":\"audio_timeout\"}");return;}
    if(!Speech::extract(pcm,bytes/2,current)){face="curious";Serial.println("{\"ok\":false,\"error\":\"silence_or_short_audio\"}");return;}
    if(String(mode)=="train"){
      if(id<0||id>=COMMAND_COUNT||!storageReady){Serial.println("{\"ok\":false,\"error\":\"training_unavailable\"}");return;}
      int s=counts[id]%EXAMPLES; // full bank replaces the last sample; clear to restart all three.
      if(counts[id]>=EXAMPLES)s=EXAMPLES-1;
      File f=SPIFFS.open(pathFor(id,s),FILE_WRITE);
      if(!f||f.write((uint8_t*)&current,sizeof(current))!=sizeof(current)){Serial.println("{\"ok\":false,\"error\":\"storage_write_failed\"}");return;}
      f.close();templates[id][s]=current;counts[id]=std::min(EXAMPLES,int(counts[id])+1);face="happy";status();
    }else if(String(mode)=="recognize")recognize();
    else Serial.println("{\"ok\":false,\"error\":\"invalid_audio_mode\"}");
    return;
  }
  Serial.println("{\"ok\":false,\"error\":\"unknown_command\"}");
}
void setup(){
  lcdOff();pinMode(0,INPUT_PULLUP);Serial.begin(115200);Serial.setTimeout(1000);
  pcm=(int16_t*)ps_malloc(128000);
  templates=(Speech::Features(*)[EXAMPLES])ps_calloc(COMMAND_COUNT*EXAMPLES,sizeof(Speech::Features));
  // No automatic format: preserve existing filesystem until explicitly provisioned.
  storageReady=SPIFFS.begin(false);if(storageReady&&templates)load();
  prefs.begin("companion",false);
  if(prefs.getBool("hardware",false)){
    mic.setPins(4,5,-1,6);speaker.setPins(7,8,9,-1);
    bool rx=mic.begin(I2S_MODE_STD,16000,I2S_DATA_BIT_WIDTH_32BIT,I2S_SLOT_MODE_MONO,I2S_STD_SLOT_LEFT);
    bool tx=speaker.begin(I2S_MODE_STD,16000,I2S_DATA_BIT_WIDTH_16BIT,I2S_SLOT_MODE_MONO);hardwareAudio=rx&&tx;
  }
  phoneSetup();
}
void loop(){
  phoneLoop();
  if(Serial.available()){String line=Serial.readStringUntil('\n');handle(line);}
  static bool down=false;bool pressed=digitalRead(0)==LOW;
  if(phoneConnected&&pressed&&!down)phoneMessage("wake");
  if(hardwareAudio&&pressed&&!down&&pcm){
    face="listening";
    // Fixed 2.5 second push-to-talk window; INMP441 uses 24-bit samples in 32-bit slots.
    for(int i=0;i<40000;i++){int32_t sample=0;mic.readBytes((char*)&sample,4);pcm[i]=std::max(-32768,std::min(32767,int(sample>>16)));}
    if(Speech::extract(pcm,40000,current))recognize(false);
  }
  down=pressed;delay(1);
}
