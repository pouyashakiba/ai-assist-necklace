#pragma once
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <BLESecurity.h>
#include <cJSON.h>

// Protocol 2: newline-delimited JSON control/events, sequenced PCM16 audio.
// JSON is fragmented at the GATT layer, never assumed to fit one ATT packet.
constexpr const char* PHONE_SERVICE="6E8F0001-3F2A-4D7B-9C10-4A434F4D5041";
constexpr const char* PHONE_CONTROL="6E8F0002-3F2A-4D7B-9C10-4A434F4D5041";
constexpr const char* PHONE_EVENTS="6E8F0003-3F2A-4D7B-9C10-4A434F4D5041";
constexpr const char* PHONE_AUDIO_IN="6E8F0004-3F2A-4D7B-9C10-4A434F4D5041";
constexpr const char* PHONE_AUDIO_OUT="6E8F0005-3F2A-4D7B-9C10-4A434F4D5041";
BLEServer* phoneServer=nullptr;
BLECharacteristic *phoneEvents=nullptr,*phoneAudioOut=nullptr;
volatile bool phoneConnected=false,phoneAudioError=false,phoneAudioAccepting=false;
bool phoneBLEReady=false,phoneUSBMirror=false,phoneAudioPlaying=false;
uint8_t* phoneAudioBuffer=nullptr;
size_t phoneAudioExpected=0,phoneAudioReceived=0,phoneAudioPlayed=0;
uint16_t phoneAudioSequence=0;
int phoneCacheID=-1;
portMUX_TYPE phoneMux=portMUX_INITIALIZER_UNLOCKED;
struct PhoneCommand { char json[4096]; };
QueueHandle_t phoneQueue=nullptr;
String phonePendingID,phonePendingText;
uint32_t phoneBootID=0,phoneRequestNumber=0,phoneLastSend=0,phoneCooldown=0;

void handle(String line);
void status();
void recognize(bool usb);

void phoneEvent(cJSON* event){
  char* encoded=cJSON_PrintUnformatted(event);if(!encoded)return;
  if(phoneUSBMirror)Serial.println(encoded);
  if(phoneConnected&&phoneEvents){
    String line=String(encoded)+"\n";
    for(size_t offset=0;offset<line.length()&&phoneConnected;offset+=20){
      size_t size=std::min(size_t(20),line.length()-offset);
      phoneEvents->setValue((uint8_t*)line.c_str()+offset,size);phoneEvents->notify();delay(3);
    }
  }
  free(encoded);
}
void phoneMessage(const char* type,const char* message=nullptr){
  cJSON* event=cJSON_CreateObject();cJSON_AddStringToObject(event,"type",type);
  if(message)cJSON_AddStringToObject(event,"message",message);phoneEvent(event);cJSON_Delete(event);
}
void phoneStatus(){
  cJSON* event=cJSON_CreateObject();cJSON_AddStringToObject(event,"type","status");
  cJSON_AddBoolToObject(event,"hardware_audio",hardwareAudio);cJSON_AddStringToObject(event,"lcd","off");
  cJSON_AddStringToObject(event,"language","en");cJSON_AddStringToObject(event,"asr","trained_phrases");
  cJSON_AddNumberToObject(event,"protocol",2);cJSON_AddNumberToObject(event,"wake_samples",counts[5]);
  phoneEvent(event);cJSON_Delete(event);
}
void phoneDiscardAudio(){
  portENTER_CRITICAL(&phoneMux);uint8_t* old=phoneAudioBuffer;phoneAudioBuffer=nullptr;phoneAudioAccepting=false;
  phoneAudioPlaying=false;phoneAudioExpected=phoneAudioReceived=phoneAudioPlayed=0;portEXIT_CRITICAL(&phoneMux);
  if(old)free(old);
}
void phoneTransmitText(){
  if(phonePendingID.isEmpty())return;
  cJSON* event=cJSON_CreateObject();cJSON_AddStringToObject(event,"type","text");
  cJSON_AddStringToObject(event,"id",phonePendingID.c_str());cJSON_AddStringToObject(event,"text",phonePendingText.c_str());
  phoneEvent(event);cJSON_Delete(event);phoneLastSend=millis();
}
bool phoneRecognized(int id){
  if(!phoneConnected)return false;
  if(id<0||id>=COMMAND_COUNT){phoneMessage("error","This phrase was not recognized. Current onboard speech is limited to trained commands.");return true;}
  if(!phonePendingID.isEmpty()){phoneMessage("error","The previous question is still waiting for the phone.");return true;}
  char request[40];snprintf(request,sizeof(request),"%08lx-%lu",(unsigned long)phoneBootID,(unsigned long)++phoneRequestNumber);
  phonePendingID=request;phonePendingText=COMMANDS[id].phrase;phoneTransmitText();return true;
}

class PhoneServerCallbacks: public BLEServerCallbacks {
  void onConnect(BLEServer*) override { phoneConnected=true; }
  void onDisconnect(BLEServer*) override { phoneConnected=false;phoneAudioError=true;BLEDevice::startAdvertising(); }
};
class PhoneControlCallbacks: public BLECharacteristicCallbacks {
  String incoming;
  void onWrite(BLECharacteristic* characteristic) override {
    String chunk=characteristic->getValue();
    for(size_t i=0;i<chunk.length();i++){
      if(chunk[i]=='\n'){
        if(incoming.length()&&incoming.length()<4096){PhoneCommand* command=(PhoneCommand*)ps_malloc(sizeof(PhoneCommand));if(command){memcpy(command->json,incoming.c_str(),incoming.length()+1);if(xQueueSend(phoneQueue,&command,0)!=pdTRUE){free(command);phoneAudioError=true;}}else phoneAudioError=true;}
        incoming="";
      }else if(incoming.length()<4095)incoming+=chunk[i];
      else {incoming="";phoneAudioError=true;}
    }
  }
};
class PhoneAudioCallbacks: public BLECharacteristicCallbacks {
  void onWrite(BLECharacteristic* characteristic) override {
    String packet=characteristic->getValue();if(packet.length()<3){phoneAudioError=true;return;}
    const uint8_t* bytes=(const uint8_t*)packet.c_str();uint16_t sequence=bytes[0]|(uint16_t(bytes[1])<<8);size_t size=packet.length()-2;
    portENTER_CRITICAL(&phoneMux);
    if(!phoneAudioAccepting||!phoneAudioBuffer||sequence!=phoneAudioSequence||phoneAudioReceived+size>phoneAudioExpected){phoneAudioError=true;phoneAudioAccepting=false;}
    else {memcpy(phoneAudioBuffer+phoneAudioReceived,bytes+2,size);phoneAudioReceived+=size;phoneAudioSequence++;}
    portEXIT_CRITICAL(&phoneMux);
  }
};

void phoneSetup(){
  phoneBootID=esp_random();phoneQueue=xQueueCreate(2,sizeof(PhoneCommand*));if(!phoneQueue)return;
  BLEDevice::init("Little Companion");BLEDevice::setMTU(185);
  BLESecurity::setAuthenticationMode(true,false,true);BLESecurity::setCapability(ESP_IO_CAP_NONE);
  phoneServer=BLEDevice::createServer();phoneServer->setCallbacks(new PhoneServerCallbacks());
  BLEService* service=phoneServer->createService(BLEUUID(PHONE_SERVICE),24);
  BLECharacteristic* control=service->createCharacteristic(PHONE_CONTROL,BLECharacteristic::PROPERTY_WRITE);
  control->setAccessPermissions(ESP_GATT_PERM_WRITE_ENCRYPTED);control->setCallbacks(new PhoneControlCallbacks());
  phoneEvents=service->createCharacteristic(PHONE_EVENTS,BLECharacteristic::PROPERTY_NOTIFY);
  BLE2902* eventDescriptor=new BLE2902();eventDescriptor->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED|ESP_GATT_PERM_WRITE_ENCRYPTED);phoneEvents->addDescriptor(eventDescriptor);
  BLECharacteristic* audioIn=service->createCharacteristic(PHONE_AUDIO_IN,BLECharacteristic::PROPERTY_WRITE);
  audioIn->setAccessPermissions(ESP_GATT_PERM_WRITE_ENCRYPTED);audioIn->setCallbacks(new PhoneAudioCallbacks());
  phoneAudioOut=service->createCharacteristic(PHONE_AUDIO_OUT,BLECharacteristic::PROPERTY_NOTIFY);
  BLE2902* audioDescriptor=new BLE2902();audioDescriptor->setAccessPermissions(ESP_GATT_PERM_READ_ENCRYPTED|ESP_GATT_PERM_WRITE_ENCRYPTED);phoneAudioOut->addDescriptor(audioDescriptor);
  service->start();BLEAdvertising* advertising=BLEDevice::getAdvertising();advertising->addServiceUUID(PHONE_SERVICE);advertising->setScanResponse(true);advertising->start();phoneBLEReady=true;
}

void phoneCapture(int ms){
  if(!hardwareAudio||!pcm){phoneMessage("error","I2S audio is not enabled. Use the app Preview tab.");return;}
  ms=std::max(300,std::min(4000,ms));int samples=ms*16;
  face="listening";phoneMessage("recording");
  for(int i=0;i<samples;i++){int32_t sample=0;mic.readBytes((char*)&sample,4);pcm[i]=std::max(-32768,std::min(32767,int(sample>>16)));}
  cJSON* event=cJSON_CreateObject();cJSON_AddStringToObject(event,"type","audio_begin");cJSON_AddNumberToObject(event,"bytes",samples*2);cJSON_AddNumberToObject(event,"rate",16000);phoneEvent(event);cJSON_Delete(event);
  uint16_t sequence=0;uint8_t packet[20];const uint8_t* data=(const uint8_t*)pcm;
  // 20-byte packets work even before a larger MTU is negotiated.
  for(int offset=0;offset<samples*2&&phoneConnected;offset+=18){int count=std::min(18,samples*2-offset);packet[0]=sequence&255;packet[1]=sequence>>8;memcpy(packet+2,data+offset,count);phoneAudioOut->setValue(packet,count+2);phoneAudioOut->notify();sequence++;delay(2);}
  phoneMessage("audio_end");
}

void phoneHandleJSON(const String& line){
  cJSON* command=cJSON_Parse(line.c_str());
  if(!command){phoneMessage("error","Invalid JSON control frame.");return;}
  const cJSON* op=cJSON_GetObjectItemCaseSensitive(command,"op");
  if(!cJSON_IsString(op)){cJSON_Delete(command);phoneMessage("error","Missing operation.");return;}
  String operation=op->valuestring;
  if(operation=="status")phoneStatus();
  else if(operation=="face"){
    cJSON* value=cJSON_GetObjectItemCaseSensitive(command,"value");
    if(cJSON_IsString(value)){String requested=value->valuestring;const char* allowed[]={"neutral","happy","laughing","shy","curious","surprised","sleepy","sleeping","affectionate","playful","sad","listening"};bool valid=false;for(auto name:allowed)if(requested==name)valid=true;if(valid)face=requested;else phoneMessage("error","Unknown face.");}
  }else if(operation=="hardware"){
    cJSON* enabled=cJSON_GetObjectItemCaseSensitive(command,"enabled");
    // Existing USB handler performs pin setup; its status stays on USB.
    handle(cJSON_IsTrue(enabled)?"HARDWARE ON":"HARDWARE OFF");phoneStatus();
  }else if(operation=="capture"){
    cJSON* ms=cJSON_GetObjectItemCaseSensitive(command,"ms");phoneCapture(cJSON_IsNumber(ms)?ms->valueint:2500);
  }else if(operation=="text_ack"){
    cJSON* id=cJSON_GetObjectItemCaseSensitive(command,"id");if(cJSON_IsString(id)&&phonePendingID==id->valuestring){phonePendingID="";phonePendingText="";}
  }else if(operation=="reply"){
    cJSON* text=cJSON_GetObjectItemCaseSensitive(command,"text");cJSON* mood=cJSON_GetObjectItemCaseSensitive(command,"face");
    if(cJSON_IsString(text)){if(cJSON_IsString(mood))face=mood->valuestring;phoneMessage("reply_received");}
  }else if(operation=="stop"){
    phoneDiscardAudio();face="neutral";phoneMessage("playback_end");
  }else if(operation=="audio_start"){
    cJSON* bytes=cJSON_GetObjectItemCaseSensitive(command,"bytes");cJSON* cache=cJSON_GetObjectItemCaseSensitive(command,"cache");int cacheID=cJSON_IsNumber(cache)?cache->valueint:-1;
    int size=cJSON_IsNumber(bytes)?bytes->valueint:0;
    if(size<=0||size>2000000||size%2||(!hardwareAudio&&(cacheID<0||cacheID>12))){phoneMessage("error","Invalid audio size or I2S output disabled.");}
    else {phoneDiscardAudio();uint8_t* buffer=(uint8_t*)ps_malloc(size);if(!buffer)phoneMessage("error","Insufficient audio memory.");else{portENTER_CRITICAL(&phoneMux);phoneAudioBuffer=buffer;phoneAudioExpected=size;phoneAudioReceived=0;phoneAudioSequence=0;phoneCacheID=cacheID;phoneAudioAccepting=true;portEXIT_CRITICAL(&phoneMux);phoneMessage("audio_ready");}}
  }else if(operation=="audio_commit"){
    if(!phoneAudioBuffer||phoneAudioReceived!=phoneAudioExpected){phoneMessage("error","Incomplete audio transfer.");phoneDiscardAudio();}
    else if(phoneCacheID>=0){
      File file=SPIFFS.open("/voice"+String(phoneCacheID)+".pcm",FILE_WRITE);
      bool saved=file&&file.write(phoneAudioBuffer,phoneAudioExpected)==phoneAudioExpected;file.close();phoneDiscardAudio();phoneMessage(saved?"cache_saved":"error",saved?nullptr:"Could not save standalone voice.");
    }else{phoneAudioAccepting=false;phoneAudioPlaying=true;phoneAudioPlayed=0;face="happy";phoneMessage("playback_begin");}
  }else phoneMessage("error","Unknown control operation.");
  cJSON_Delete(command);
}

void phoneLoop(){
  if(phoneAudioError){phoneAudioError=false;phoneDiscardAudio();phoneMessage("error","Bluetooth audio frame was lost or the connection ended. Please retry.");}
  PhoneCommand* command=nullptr;
  if(phoneQueue&&xQueueReceive(phoneQueue,&command,0)==pdTRUE){phoneHandleJSON(command->json);free(command);}
  if(phoneConnected&&!phonePendingID.isEmpty()&&millis()-phoneLastSend>3000)phoneTransmitText();
  if(phoneAudioPlaying&&phoneAudioBuffer){
    size_t count=std::min(size_t(1024),phoneAudioExpected-phoneAudioPlayed);
    size_t sent=speaker.write(phoneAudioBuffer+phoneAudioPlayed,count);phoneAudioPlayed+=sent;
    if(sent==0||phoneAudioPlayed>=phoneAudioExpected){phoneDiscardAudio();phoneCooldown=millis()+1000;phoneMessage("playback_end");}
  }
}
