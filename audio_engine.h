/**
 * audio_engine.h
 * 
 * C++ Native Audio Engine for Quran Playback
 * Uses Oboe for low-latency audio on Android
 * 
 * Purpose: Achieve <10ms seek latency for memorization loops
 * Platform: Android (Oboe), iOS (AVAudioEngine - separate implementation)
 * 
 * Design Principles:
 * - Direct hardware access via Oboe
 * - Gapless Ayah transitions
 * - Sub-10ms seek performance
 * - Separate from UI audio track (just_audio handles UI sounds)
 */

#ifndef QURAN_AUDIO_ENGINE_H
#define QURAN_AUDIO_ENGINE_H

#include <oboe/Oboe.h>
#include <string>
#include <memory>
#include <functional>
#include <atomic>

namespace quran {

/**
 * Audio playback states
 * Exposed to Dart via FFI
 */
enum class PlaybackState {
    IDLE = 0,
    LOADING = 1,
    PLAYING = 2,
    PAUSED = 3,
    STOPPED = 4,
    REPEATING = 5,
    ERROR = 6
};

/**
 * Audio focus states (Android AudioManager)
 */
enum class AudioFocusState {
    GAIN = 0,
    LOSS = 1,
    LOSS_TRANSIENT = 2,
    LOSS_TRANSIENT_CAN_DUCK = 3
};

/**
 * Playback callbacks
 * Used to notify Dart layer of state changes
 */
struct PlaybackCallbacks {
    std::function<void(PlaybackState)> onStateChanged;
    std::function<void(double)> onPositionChanged;  // Position in seconds
    std::function<void()> onAyahEnded;
    std::function<void(const std::string&)> onError;
};

/**
 * AudioEngine
 * 
 * Main audio playback engine using Oboe
 * Handles audio focus, volume ducking, and low-latency playback
 */
class AudioEngine : public oboe::AudioStreamDataCallback,
                   public oboe::AudioStreamErrorCallback {
public:
    /**
     * Constructor
     * Initializes Oboe audio stream
     */
    AudioEngine();
    
    /**
     * Destructor
     * Cleans up Oboe resources
     */
    ~AudioEngine();
    
    // ========================================================================
    // PLAYBACK CONTROL
    // ========================================================================
    
    /**
     * Load an audio file and prepare for playback
     * 
     * @param filePath Absolute path to MP3 file
     * @param preload If true, load into buffer immediately
     * @return true if loaded successfully
     */
    bool loadAudio(const std::string& filePath, bool preload = false);
    
    /**
     * Start playback from current position
     * 
     * @return true if playback started
     */
    bool play();
    
    /**
     * Pause playback
     * Preserves current position for resume
     * 
     * @return true if paused successfully
     */
    bool pause();
    
    /**
     * Stop playback and reset position to 0
     * 
     * @return true if stopped successfully
     */
    bool stop();
    
    /**
     * Seek to specific position in audio
     * TARGET: <10ms latency
     * 
     * @param positionSeconds Position in seconds
     * @return true if seek successful
     */
    bool seekTo(double positionSeconds);
    
    /**
     * Get current playback position
     * 
     * @return Position in seconds
     */
    double getCurrentPosition() const;
    
    /**
     * Get total duration of loaded audio
     * 
     * @return Duration in seconds
     */
    double getDuration() const;
    
    /**
     * Check if audio is currently playing
     * 
     * @return true if playing
     */
    bool isPlaying() const;
    
    /**
     * Get current playback state
     * 
     * @return Current PlaybackState
     */
    PlaybackState getState() const;
    
    // ========================================================================
    // VOLUME & AUDIO FOCUS
    // ========================================================================
    
    /**
     * Set playback volume
     * 
     * @param volume Volume level (0.0 to 1.0)
     */
    void setVolume(float volume);
    
    /**
     * Get current volume
     * 
     * @return Volume level (0.0 to 1.0)
     */
    float getVolume() const;
    
    /**
     * Duck volume (reduce for UI sounds / TalkBack)
     * 
     * @param duckLevel Target volume (e.g., 0.3 for 30%)
     * @param fadeMs Fade duration in milliseconds (default 100ms)
     */
    void duckVolume(float duckLevel, int fadeMs = 100);
    
    /**
     * Restore volume to previous level before ducking
     * 
     * @param fadeMs Fade duration in milliseconds (default 500ms)
     */
    void restoreVolume(int fadeMs = 500);
    
    /**
     * Handle Android audio focus changes
     * Called by Java/Kotlin layer via JNI
     * 
     * @param focusState New audio focus state
     */
    void onAudioFocusChange(AudioFocusState focusState);
    
    // ========================================================================
    // PLAYBACK SPEED
    // ========================================================================
    
    /**
     * Set playback speed
     * Uses WSOLA (Waveform Similarity Overlap-Add) to preserve pitch
     * 
     * @param speed Speed multiplier (0.5x to 2.0x)
     */
    void setPlaybackSpeed(float speed);
    
    /**
     * Get current playback speed
     * 
     * @return Speed multiplier
     */
    float getPlaybackSpeed() const;
    
    // ========================================================================
    // PRELOADING & BUFFERING
    // ========================================================================
    
    /**
     * Preload next Ayah into buffer
     * Called when current playback reaches 80% progress
     * 
     * @param filePath Path to next Ayah audio file
     * @return true if preloaded successfully
     */
    bool preloadNext(const std::string& filePath);
    
    /**
     * Switch to preloaded buffer (gapless transition)
     * 
     * @return true if switched successfully
     */
    bool switchToPreloaded();
    
    /**
     * Clear preload buffer to free memory
     */
    void clearPreloadBuffer();
    
    // ========================================================================
    // CALLBACKS
    // ========================================================================
    
    /**
     * Set playback callbacks for Dart FFI
     * 
     * @param callbacks Callback functions
     */
    void setCallbacks(const PlaybackCallbacks& callbacks);
    
    // ========================================================================
    // OBOE CALLBACKS (INTERNAL)
    // ========================================================================
    
    /**
     * Oboe data callback
     * Called by audio thread to fill output buffer
     * 
     * @param audioStream The audio stream
     * @param audioData Output buffer to fill
     * @param numFrames Number of frames to write
     * @return DataCallbackResult
     */
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* audioStream,
        void* audioData,
        int32_t numFrames) override;
    
    /**
     * Oboe error callback
     * Called when audio stream encounters an error
     * 
     * @param audioStream The audio stream
     * @param error Error code
     */
    void onErrorAfterClose(
        oboe::AudioStream* audioStream,
        oboe::Result error) override;
    
private:
    // ========================================================================
    // PRIVATE MEMBERS
    // ========================================================================
    
    std::shared_ptr<oboe::AudioStream> audioStream_;
    PlaybackState state_;
    std::atomic<float> volume_;
    std::atomic<float> targetVolume_;  // For fade in/out
    std::atomic<float> playbackSpeed_;
    
    // Audio buffers
    std::unique_ptr<uint8_t[]> audioBuffer_;
    std::unique_ptr<uint8_t[]> preloadBuffer_;
    size_t bufferSize_;
    size_t preloadBufferSize_;
    std::atomic<size_t> currentPosition_;  // In bytes
    size_t totalSize_;
    
    // Timing
    std::atomic<double> durationSeconds_;
    std::atomic<double> currentPositionSeconds_;
    
    // Audio focus
    std::atomic<float> volumeBeforeDuck_;
    AudioFocusState audioFocusState_;
    
    // Callbacks
    PlaybackCallbacks callbacks_;
    
    // Decoder
    std::unique_ptr<class AudioDecoder> decoder_;  // MP3 decoder
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    /**
     * Initialize Oboe audio stream
     * 
     * @return true if initialized successfully
     */
    bool initializeStream();
    
    /**
     * Close and release audio stream
     */
    void closeStream();
    
    /**
     * Decode audio file into buffer
     * 
     * @param filePath Path to audio file
     * @param buffer Output buffer
     * @param bufferSize Output buffer size
     * @return true if decoded successfully
     */
    bool decodeAudioFile(const std::string& filePath, 
                         std::unique_ptr<uint8_t[]>& buffer,
                         size_t& bufferSize);
    
    /**
     * Apply volume fade (for ducking/restore)
     * 
     * @param fromVolume Starting volume
     * @param toVolume Target volume
     * @param durationMs Fade duration
     */
    void applyVolumeFade(float fromVolume, float toVolume, int durationMs);
    
    /**
     * Notify state change to Dart callbacks
     * 
     * @param newState New playback state
     */
    void notifyStateChange(PlaybackState newState);
    
    /**
     * Update position and trigger callbacks
     * Called periodically during playback
     */
    void updatePosition();
};

} // namespace quran

// ============================================================================
// FFI EXPORTS (C API for Dart)
// ============================================================================

extern "C" {

/**
 * Create audio engine instance
 * 
 * @return Pointer to AudioEngine (opaque handle for Dart)
 */
void* audio_engine_create();

/**
 * Destroy audio engine instance
 * 
 * @param engine Pointer from audio_engine_create
 */
void audio_engine_destroy(void* engine);

/**
 * Load audio file
 * 
 * @param engine AudioEngine pointer
 * @param filePath Path to MP3 file (UTF-8)
 * @param preload Preload into buffer
 * @return 1 if successful, 0 if failed
 */
int audio_engine_load(void* engine, const char* filePath, int preload);

/**
 * Play audio
 * 
 * @param engine AudioEngine pointer
 * @return 1 if successful, 0 if failed
 */
int audio_engine_play(void* engine);

/**
 * Pause audio
 * 
 * @param engine AudioEngine pointer
 * @return 1 if successful, 0 if failed
 */
int audio_engine_pause(void* engine);

/**
 * Stop audio
 * 
 * @param engine AudioEngine pointer
 * @return 1 if successful, 0 if failed
 */
int audio_engine_stop(void* engine);

/**
 * Seek to position
 * 
 * @param engine AudioEngine pointer
 * @param positionSeconds Position in seconds
 * @return 1 if successful, 0 if failed
 */
int audio_engine_seek(void* engine, double positionSeconds);

/**
 * Get current position
 * 
 * @param engine AudioEngine pointer
 * @return Position in seconds
 */
double audio_engine_get_position(void* engine);

/**
 * Get duration
 * 
 * @param engine AudioEngine pointer
 * @return Duration in seconds
 */
double audio_engine_get_duration(void* engine);

/**
 * Check if playing
 * 
 * @param engine AudioEngine pointer
 * @return 1 if playing, 0 if not
 */
int audio_engine_is_playing(void* engine);

/**
 * Get current state
 * 
 * @param engine AudioEngine pointer
 * @return PlaybackState as integer
 */
int audio_engine_get_state(void* engine);

/**
 * Set volume
 * 
 * @param engine AudioEngine pointer
 * @param volume Volume (0.0 to 1.0)
 */
void audio_engine_set_volume(void* engine, float volume);

/**
 * Get volume
 * 
 * @param engine AudioEngine pointer
 * @return Volume (0.0 to 1.0)
 */
float audio_engine_get_volume(void* engine);

/**
 * Duck volume
 * 
 * @param engine AudioEngine pointer
 * @param duckLevel Target volume (e.g., 0.3)
 * @param fadeMs Fade duration in ms
 */
void audio_engine_duck_volume(void* engine, float duckLevel, int fadeMs);

/**
 * Restore volume
 * 
 * @param engine AudioEngine pointer
 * @param fadeMs Fade duration in ms
 */
void audio_engine_restore_volume(void* engine, int fadeMs);

/**
 * Handle audio focus change
 * 
 * @param engine AudioEngine pointer
 * @param focusState AudioFocusState as integer
 */
void audio_engine_on_audio_focus_change(void* engine, int focusState);

/**
 * Set playback speed
 * 
 * @param engine AudioEngine pointer
 * @param speed Speed multiplier (0.5 to 2.0)
 */
void audio_engine_set_speed(void* engine, float speed);

/**
 * Get playback speed
 * 
 * @param engine AudioEngine pointer
 * @return Speed multiplier
 */
float audio_engine_get_speed(void* engine);

/**
 * Preload next audio file
 * 
 * @param engine AudioEngine pointer
 * @param filePath Path to next file
 * @return 1 if successful, 0 if failed
 */
int audio_engine_preload_next(void* engine, const char* filePath);

/**
 * Switch to preloaded buffer (gapless)
 * 
 * @param engine AudioEngine pointer
 * @return 1 if successful, 0 if failed
 */
int audio_engine_switch_to_preloaded(void* engine);

/**
 * Clear preload buffer
 * 
 * @param engine AudioEngine pointer
 */
void audio_engine_clear_preload(void* engine);

// ============================================================================
// CALLBACK REGISTRATION
// ============================================================================

/**
 * Callback function types for Dart
 */
typedef void (*StateChangedCallback)(int state);
typedef void (*PositionChangedCallback)(double position);
typedef void (*AyahEndedCallback)();
typedef void (*ErrorCallback)(const char* error);

/**
 * Register callbacks
 * 
 * @param engine AudioEngine pointer
 * @param onStateChanged State change callback
 * @param onPositionChanged Position update callback
 * @param onAyahEnded Ayah completion callback
 * @param onError Error callback
 */
void audio_engine_set_callbacks(
    void* engine,
    StateChangedCallback onStateChanged,
    PositionChangedCallback onPositionChanged,
    AyahEndedCallback onAyahEnded,
    ErrorCallback onError
);

} // extern "C"

#endif // QURAN_AUDIO_ENGINE_H
