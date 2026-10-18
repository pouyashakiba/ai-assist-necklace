#pragma once
#include <math.h>
#include <stdint.h>
#include <algorithm>

// Speaker-dependent, isolated-word recognizer. 16 kHz signed PCM -> MFCC -> DTW.
// No STT/LLM and no claim of general Persian speech recognition.
namespace Speech {
constexpr int D=12, MAX_FRAMES=110, FFT=512, MEL=24;
struct Features {uint16_t frames=0; float v[MAX_FRAMES][D];};
inline void fft(float* re,float* im) {
  for(int i=1,j=0;i<FFT;i++) {int bit=FFT>>1;for(;j&bit;bit>>=1)j^=bit;j^=bit;if(i<j){std::swap(re[i],re[j]);std::swap(im[i],im[j]);}}
  for(int n=2;n<=FFT;n<<=1) for(int k=0;k<FFT;k+=n) for(int j=0;j<n/2;j++) {
    float a=-2*M_PI*j/n,c=cosf(a),s=sinf(a);int u=k+j,v=u+n/2;
    float r=c*re[v]-s*im[v],z=s*re[v]+c*im[v];re[v]=re[u]-r;im[v]=im[u]-z;re[u]+=r;im[u]+=z;
  }
}
inline bool extract(const int16_t* pcm,int count,Features& out) {
  out.frames=0;
  if(count<3200 || count>64000)return false;
  float peak=0;
  for(int p=0;p+400<=count;p+=160){float e=0;for(int j=0;j<400;j++)e+=float(pcm[p+j])*pcm[p+j];peak=std::max(peak,sqrtf(e/400));}
  if(peak<180)return false;
  int begin=count,end=0;float threshold=std::max(130.f,peak*.12f);
  for(int p=0;p+400<=count;p+=160){float e=0;for(int j=0;j<400;j++)e+=float(pcm[p+j])*pcm[p+j];if(sqrtf(e/400)>threshold){begin=std::min(begin,p);end=p+400;}}
  if(end-begin<2400)return false;
  begin=std::max(0,begin-320);end=std::min(count,end+320);
  int available=(end-begin-400)/160+1;
  out.frames=std::min(MAX_FRAMES,available);
  int bins[MEL+2];float maxMel=2595*log10f(1+8000.f/700);
  for(int m=0;m<MEL+2;m++)bins[m]=floorf(513*700*(powf(10,maxMel*m/(MEL+1)/2595)-1)/16000);
  float re[FFT],im[FFT],lm[MEL];
  for(int t=0;t<out.frames;t++) {
    int p=begin+int(float(t)*(available-1)/std::max(1,int(out.frames)-1))*160;
    for(int i=0;i<FFT;i++){re[i]=i<400?(pcm[p+i]-(i?0.97f*pcm[p+i-1]:0))*(.54f-.46f*cosf(2*M_PI*i/399))/32768.f:0;im[i]=0;}
    fft(re,im);
    for(int m=0;m<MEL;m++) {float e=0;for(int b=bins[m];b<bins[m+2]&&b<=256;b++){float w=b<bins[m+1]?float(b-bins[m])/std::max(1,bins[m+1]-bins[m]):float(bins[m+2]-b)/std::max(1,bins[m+2]-bins[m+1]);e+=(re[b]*re[b]+im[b]*im[b])*w;}lm[m]=logf(std::max(e,1e-9f));}
    for(int d=0;d<D;d++){float sum=0;for(int m=0;m<MEL;m++)sum+=lm[m]*cosf(M_PI*(d+1)*(m+.5f)/MEL);out.v[t][d]=sum/12;}
  }
  // Cepstral mean subtraction suppresses fixed microphone/channel coloration.
  for(int d=0;d<D;d++){float mean=0;for(int t=0;t<out.frames;t++)mean+=out.v[t][d];mean/=out.frames;for(int t=0;t<out.frames;t++)out.v[t][d]-=mean;}
  return true;
}
inline float distance(const Features& a,const Features& b) {
  if(!a.frames||!b.frames)return 1e9;
  float prev[MAX_FRAMES+1],cur[MAX_FRAMES+1];
  for(int j=0;j<=b.frames;j++)prev[j]=1e9;prev[0]=0;
  for(int i=1;i<=a.frames;i++){
    cur[0]=1e9;
    for(int j=1;j<=b.frames;j++){
      float cost=0;for(int d=0;d<D;d++){float delta=a.v[i-1][d]-b.v[j-1][d];cost+=delta*delta;}cost=sqrtf(cost/D);
      cur[j]=cost+std::min(prev[j],std::min(cur[j-1],prev[j-1]));
    }
    std::copy(cur,cur+b.frames+1,prev);
  }
  return prev[b.frames]/(a.frames+b.frames);
}
}
