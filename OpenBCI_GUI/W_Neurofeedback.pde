
////////////////////////////////////////////////////
//
//    W_neurofeedback.pde
//
//    A tone neurofeedback for alpha band (7.5-12.5Hz) for all channels. The tone is hardcoded. The feedback is
//    both with amplitude of the tone and slight changes of frequency. The tone is different for each feedback channel. 
//    This is a pretty basic, but working feedback proof of concept.
//    You can also do feedback on hemicoherence and enable alpha+/beta- feedback
//    instead of alpha+ only
//
//    Created by: Juraj Bednár
//
///////////////////////////////////////////////////,

import ddf.minim.Minim;
import ddf.minim.AudioOutput;
import ddf.minim.ugens.*;

class W_neurofeedback extends Widget {

  Minim       minim;
  AudioOutput out;
  Oscil[]       waves;
  int numHarmonic = 2; // number of harmonic frequencies for each wave
  
  boolean chordMode = true;
  float[][] chordFrequencies = {
    { 261.63, 329.63, 392.00 }, // C chord
    { 349.23, 440.00, 261.63 }, // F chord
    { 392.00, 493.88, 293.66 }, // G chord
    { 2*261.63, 2*329.63, 2*392.00 }, // C chord
    { 2*349.23, 2*440.00, 2*261.63 }, // F chord
    { 2*392.00, 2*493.88, 2*293.66 }, // G chord
    { 3*261.63, 3*329.63, 3*392.00 }, // C chord
    { 3*349.23, 3*440.00, 3*261.63 }, // F chord
    { 3*392.00, 3*493.88, 3*293.66 } // G chord
  };
  
  int hemicoherence_chan1 = 0;
  int hemicoherence_chan2 = 1;

  float noise_cutoff_level = 3;
  float beta_factor = 0.6; // how much does beta factor lower the tone in alpha+beta-
  boolean hemicoherence_enabled = false;
  boolean alphaOnly = true;
  float[] hemicoherenceMemory;
  final int hemicoherenceMemoryLength = 10;
  int hemicoherenceMemoryPointer = 0;
  float[] amplitudeCounters;
  float[] displayAmplitudeCounters;
  float[] previousAmplitudeCounters;
  int[] amplitudeCountersRaise;
  
  long lastUpdate;
  long epochLength = 60*1000;


  W_neurofeedback(PApplet _parent) {
    super(_parent); //calls the parent CONSTRUCTOR method of Widget (DON'T REMOVE)
  
    List <String> channelList = new ArrayList<String>();
    for (int i = 0; i < nchan; i++) {
      channelList.add(Integer.toString(i + 1));
    }
  
    addDropdown("FeedbackType", "Type", Arrays.asList("alph+", "alph+ bet-"), 0);
    addDropdown("NoiseCutoffLevel", "Cutoff", Arrays.asList("2 uV", "3 uV", "4 uV", "5 uV",
        "6 uV", "7 uV", "8 uV", "9 uV", "10 uV", "11 uV", "12 uV", "13 uV", "14 uV", "15 uV"), 10);

    addDropdown("BetaFactor", "Beta%", Arrays.asList("10%", "20%", "30%", "40%",
        "50%", "60%", "70%", "80%", "90%", "100%"), 6);


    addDropdown("HemicoherenceEnable", "HC Feedback", Arrays.asList("Off", "On"), 0);
    addDropdown("HemicoherenceChan1", "Chan A", channelList, hemicoherence_chan1);
    addDropdown("HemicoherenceChan2", "Chan B", channelList, hemicoherence_chan2);
  
    hemicoherenceMemory = new float[hemicoherenceMemoryLength];
    for (int i=0;i<hemicoherenceMemoryLength;i++) {
      hemicoherenceMemory[i] = 0f;
    }
    
    minim = new Minim(this);
    out = minim.getLineOut();
    float panFactor = 0f;                 // 1 means total left/right pan, 0 means MONO (all tones in both
                                          // channels, 0.8f means mixing 80/20, good for headphones

    if (chordMode) numHarmonic = 3;       // for chords, we need three frequencies for each chord

    resetEpoch();

    // create a sine wave Oscil, set to 440 Hz, at 0.5 amplitude
    waves = new Oscil[(nchan + 1) * numHarmonic]; // we have one tone for hemicoherence, thus nchan+1
    for (int i=0 ; i<nchan + 1; i++) 
      for (int j=0 ; j<numHarmonic ; j++) {
      waves[(i*numHarmonic)+j] = new Oscil( baseFrequency(i, j, 0f), 0.0f, Waves.SINE );
      if (i%2 == 0) {
        Pan left = new Pan((-1f) * panFactor);
        waves[(i*numHarmonic)+j].patch( left );
        left.patch( out );
      }
      else {
        Pan right = new Pan(1f * panFactor);
        waves[(i*numHarmonic)+j].patch( right );
        right.patch(out);
      }
    }
  }

  public void resetEpoch() {
    // initialize amplitudeCounters
    amplitudeCounters = new float[nchan + 1];
    displayAmplitudeCounters = new float[nchan + 1];
    previousAmplitudeCounters = new float[nchan + 1];
    amplitudeCountersRaise = new int[nchan + 1];
    for (int i=0 ; i<nchan + 1; i++) {
      amplitudeCounters[i] = 0;
      displayAmplitudeCounters[i] = 0;
      previousAmplitudeCounters[i] = 0;
      amplitudeCountersRaise[i] = 0;
    }
    lastUpdate = System.currentTimeMillis();
  }

  private float baseFrequency(int channel, int harmonic, float amplitude) {
    if (chordMode) {
      return chordFrequencies[channel][harmonic];
    } else 
    return (400 + (channel*(400/nchan)) /* + (100*amplitude)*/) * (harmonic+1);
      
  }

  private void setTone(int channel, float amplitude) {
    for (int j=0 ; j<numHarmonic ; j++) {
      waves[(channel*numHarmonic)+j].setAmplitude(amplitude);
      // commented out - we are not changing frequency, only amplitude
      //waves[(channel*numHarmonic)+j].setFrequency(baseFrequency(channel, j, amplitude));
    }
  }

  void update(){
    super.update(); //calls the parent update() method of Widget (DON'T REMOVE)
    process(yLittleBuff_uV, dataBuffY_uV, dataBuffY_filtY_uV, fftBuff);
  }

public void process(float[][] data_newest_uV, //holds raw EEG data that is new since the last call
        float[][] data_long_uV, //holds a longer piece of buffered EEG data, of same length as will be plotted on the screen
        float[][] data_forDisplay_uV, //this data has been filtered and is ready for plotting on the screen
        FFT[] fftData) {              //holds the FFT (frequency spectrum) of the latest data

    float FFT_freq_Hz, FFT_value_uV;
    float coherence1_alpha_amplitude = 0;
    float coherence2_alpha_amplitude = 0;
    float coherence1_beta_amplitude = 0;
    float coherence2_beta_amplitude = 0;

    for (int Ichan=0;Ichan < nchan; Ichan++) {

     if (isChannelActive(Ichan)) {
      //loop over each new sample

      float alpha_amplitude = 0;
      float alpha_max_amplitude = 0;
      int alpha_samples = 0;

      float beta_amplitude = 0;
      float beta_max_amplitude = 0;
      int beta_samples = 0;


      for (int Ibin=0; Ibin < fftData[Ichan].specSize(); Ibin++){
        FFT_freq_Hz = fftData[Ichan].indexToFreq(Ibin);
        FFT_value_uV = fftData[Ichan].getBand(Ibin);
        
        if ((FFT_freq_Hz >= 7.5) && (FFT_freq_Hz <= 12.5)) { // FFT bins in alpha range
          if (FFT_value_uV > alpha_max_amplitude) alpha_max_amplitude = FFT_value_uV;
          alpha_amplitude += FFT_value_uV;
          alpha_samples++;
        }
        else if (FFT_freq_Hz > 12.5 && FFT_freq_Hz <= 30) {  // FFT bins in beta range
          if (FFT_value_uV > beta_max_amplitude) beta_max_amplitude = FFT_value_uV;
          beta_amplitude += FFT_value_uV;
          beta_samples++;
        }
     }

     if (hemicoherence_enabled) {
      if (Ichan == hemicoherence_chan1) {
        coherence1_alpha_amplitude = alpha_amplitude;
        coherence1_beta_amplitude = beta_amplitude;
      } else if (Ichan == hemicoherence_chan2) {
        coherence1_alpha_amplitude = alpha_amplitude;
        coherence1_beta_amplitude = beta_amplitude;
      }
     }


     alpha_amplitude = alpha_amplitude / alpha_samples;
     beta_amplitude = beta_amplitude / beta_samples;


     if (hemicoherence_enabled) {
      if (Ichan == hemicoherence_chan1) {
        coherence1_alpha_amplitude = alpha_amplitude;
        coherence1_beta_amplitude = beta_amplitude;
      } else if (Ichan == hemicoherence_chan2) {
        coherence1_alpha_amplitude = alpha_amplitude;
        coherence1_beta_amplitude = beta_amplitude;
      }
     }

 //    System.out.println((Ichan+1) + ": alpha: " + (alpha_amplitude/alpha_samples) + 
 //      "(max: " + alpha_max_amplitude +") over " + alpha_samples +" samples");

     if (alpha_amplitude < noise_cutoff_level) { // to avoid noise when a person is moving
       if (alphaOnly) {
        setTone(Ichan, map(alpha_amplitude, 0, noise_cutoff_level, 0, 1)); // or some other range?
        if (alpha_amplitude > noise_cutoff_level)
          recordAmplitude(Ichan, 0);
        else 
          recordAmplitude(Ichan, alpha_amplitude);
     } else { // alpha - beta
        setTone(Ichan, map(constrain(alpha_amplitude - (beta_factor * beta_amplitude), 0, noise_cutoff_level),
          0, noise_cutoff_level, 0, 1)); // or some other range?
        recordAmplitude(Ichan,
          constrain(alpha_amplitude - beta_amplitude, 0, noise_cutoff_level));
       }
     } else setTone(Ichan,0);
    } else setTone(Ichan,0);

   }

    // hemicoherence calculation
    // TODO: this is coherence of averages, not of samples
    if (hemicoherence_enabled) {
      float hemiIncoherenceAmplitude = abs(coherence1_alpha_amplitude - coherence2_alpha_amplitude);
      if (!alphaOnly) {
        hemiIncoherenceAmplitude += abs(coherence1_beta_amplitude - coherence2_beta_amplitude);
        hemiIncoherenceAmplitude = hemiIncoherenceAmplitude/2;
      }

      //System.out.println("Hemicoherence factor " + pow(0.95, hemiIncoherenceAmplitude));
      addHemiCoherence(pow(0.95, hemiIncoherenceAmplitude));
    } else setTone(nchan, 0);
  }

  void addHemiCoherence(float x) {
    hemicoherenceMemory[hemicoherenceMemoryPointer] = x;
    hemicoherenceMemoryPointer++;
    if (hemicoherenceMemoryPointer>=hemicoherenceMemoryLength)
      hemicoherenceMemoryPointer = 0;

    float averageAmplitude = 0f;
    float maxAmplitude = 0f;
    for (int i=0;i<hemicoherenceMemoryLength;i++) {
      averageAmplitude+= hemicoherenceMemory[i]; 
      if (hemicoherenceMemory[i]>maxAmplitude)
        maxAmplitude = hemicoherenceMemory[i];
    }
    averageAmplitude = averageAmplitude/hemicoherenceMemoryLength;

    //setTone(nchan, maxAmplitude);
    setTone(nchan, averageAmplitude);
    recordAmplitude(nchan, averageAmplitude);
  }

  void recordAmplitude(int chan, float amplitude) {
    amplitudeCounters[chan]+=amplitude;
    if ((System.currentTimeMillis() - lastUpdate) > epochLength)
      updateAmplitudes();
  }
  
  void updateAmplitudes() {
    for (int i=0; i<nchan; i++)
    if (isChannelActive(i)) {
      System.out.println("Channel " + (i+1) + " amplitude " + amplitudeCounters[i]);
      displayAmplitudeCounters[i] = round(amplitudeCounters[i]/100)*100; 
      amplitudeCountersRaise[i] = round(displayAmplitudeCounters[i] - previousAmplitudeCounters[i]);
      previousAmplitudeCounters[i] = displayAmplitudeCounters[i];
      amplitudeCounters[i] = 0;
    } else {
      displayAmplitudeCounters[i] = 0;
    }
    lastUpdate = System.currentTimeMillis();
  }

  void draw(){
    super.draw(); //calls the parent draw() method of Widget (DON'T REMOVE)

    pushStyle();

    color(0,0,0);
    fill(50);
    textFont(p4, 16);
    textAlign(LEFT);

    text("Amplitudes:", x+20, y+20);
    int channelIdx = 0;
    for (int i=0; i<nchan; i++)
    if (displayAmplitudeCounters[i] > 0) {
      fill(50);
      int my = y+((h / (nchan+3)) * (channelIdx+2));
      text("Channel " + (i+1), x+30, my);
      if (amplitudeCountersRaise[i] >= 0)
        fill(50,50,255);
      text(new Integer(round(displayAmplitudeCounters[i])).toString(), x+(w/3), my);
      channelIdx++;
    }
    popStyle();

  }

  void screenResized(){
    super.screenResized(); //calls the parent screenResized() method of Widget (DON'T REMOVE)

    

  }

  void mousePressed(){
    super.mousePressed(); //calls the parent mousePressed() method of Widget (DON'T REMOVE)

    /*//put your code here...
    if(widgetTemplateButton.isMouseHere()){
      widgetTemplateButton.setIsActive(true);
    }*/

  }

  void mouseReleased(){
    super.mouseReleased(); //calls the parent mouseReleased() method of Widget (DON'T REMOVE)

    //put your code here...
    /*
    if(widgetTemplateButton.isActive && widgetTemplateButton.isMouseHere()){
      widgetTemplateButton.goToURL();
    }
    widgetTemplateButton.setIsActive(false);
    */
  }


};

void NoiseCutoffLevel (int n) {
  w_neurofeedback.noise_cutoff_level = n + 2;
  w_neurofeedback.resetEpoch();
  closeAllDropdowns();
}

void BetaFactor (int n) {
  w_neurofeedback.beta_factor = (n + 1) * 0.1;
  w_neurofeedback.resetEpoch();
  closeAllDropdowns();
}

void FeedbackType(int n) {
  if (n==0) w_neurofeedback.alphaOnly = true;
  else w_neurofeedback.alphaOnly = false;
  w_neurofeedback.resetEpoch();
  closeAllDropdowns();
}

void HemicoherenceEnable(int n) {
  if (n==0) w_neurofeedback.hemicoherence_enabled = false;
  else w_neurofeedback.hemicoherence_enabled = true;
  w_neurofeedback.resetEpoch();
  closeAllDropdowns();
}

void HemicoherenceChan1(int n) {
  w_neurofeedback.hemicoherence_chan1 = n;
  w_neurofeedback.resetEpoch();
  closeAllDropdowns();
}

void HemicoherenceChan2(int n) {
  w_neurofeedback.hemicoherence_chan2 = n;
  w_neurofeedback.resetEpoch();
  closeAllDropdowns();
}
