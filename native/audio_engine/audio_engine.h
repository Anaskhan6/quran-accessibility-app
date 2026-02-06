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
 * - Deterministic callback timing
 * - Native repeat loop management
 */

#ifndef QURAN_AUDIO_ENGINE_H
#define QURAN_AUDIO_ENGINE_H

#include <oboe/Oboe.h>
#include <string>
#include <memory>
#include <functional>
#include <atomic>
#include <mutex>
#include <vector>
#include <chrono>

namespace quran {

// ============================================================================
// ENUMS
// ============================================================================

/**
 * Audio playback states
 */
enum class PlaybackState : int32_t {
    IDLE = 0,
    LOADING = 1,
    PLAYING = 2,
    PAUSED = 3,
    STOPPED = 4,
    BUFFERING = 5,
    ERROR = 6
};

/**
 * Audio focus states (Android AudioManager)
 */
enum class AudioFocusState : int32_t {
    GAIN = 0,
    LOSS = 1,
    LOSS_TRANSIENT = 2,
    LOSS_TRANSIENT_CAN_DUCK = 3
};

/**
 * Repeat modes for memorization
 */
enum class RepeatMode : int32_t {
    NONE = 0,
    SINGLE = 1,      // Single Ayah loop
    RANGE = 2,       // Range of Ayahs
    INFINITE = 3,    // Loop forever
    COUNT = 4        // Loop N times
};

// ============================================================================
// STRUCTS
// ============================================================================

/**
 * Audio configuration
 */
struct AudioConfig {
    int32_t sampleRate = 44100;
    int32_t channelCount = 2;
    int32_t framesPerBuffer = 256;
};

/**
 * Native Repeat State
 * Manages repeat loop with deterministic timing
 */
struct RepeatState {
    RepeatMode mode = RepeatMode::NONE;
    int32_t startAyah = 0;
    int32_t endAyah = 0;
    int32_t currentAyah = 0;
    int32_t iterationCount = 0;
    int32_t targetIterations = 1;
    int32_t pauseIntervalMs = 0;
    bool isActive = false;
    
    // Timing
    int64_t lastIterationTimestampNs = 0;
    int64_t pauseStartTimestampNs = 0;
};

/**
 * Buffering state info
 */
struct BufferState {
    bool isBuffering = false;
    double bufferedPosition = 0.0;
    double preloadProgress = 0.0;
};

/**
 * Expanded playback callbacks with timestamps
 * For deterministic event ordering verification
 */
struct PlaybackCallbacks {
    // State transitions with timestamps
    std::function<void(int64_t timestampNs)> onPlaybackStarted;
    std::function<void(int64_t timestampNs, double position)> onPlaybackPaused;
    std::function<void(int64_t timestampNs, double position)> onPlaybackResumed;
    std::function<void(int64_t timestampNs)> onPlaybackStopped;
    
    // Buffering
    std::function<void(bool isBuffering, double progress)> onBufferingChanged;
    
    // Seek
    std::function<void(int64_t timestampNs, double position)> onSeekCompleted;
    
    // Preload
    std::function<void(const std::string& filePath)> onPreloadCompleted;
    
    // Ayah events
    std::function<void()> onAyahEnded;
    std::function<void(double)> onPositionChanged;
    
    // Repeat events
    std::function<void(int iteration, int total)> onRepeatIteration;
    std::function<void()> onRepeatCompleted;
    
    // Errors
    std::function<void(const std::string&)> onError;
};

// ============================================================================
// AUDIO ENGINE CLASS
// ============================================================================

/**
 * AudioEngine
 * 
 * Main audio playback engine using Oboe
 * Handles deterministic callbacks, repeat loops, and gapless transitions
 */
class AudioEngine : public oboe::AudioStreamDataCallback,
                    public oboe::AudioStreamErrorCallback {
public:
    AudioEngine();
    ~AudioEngine();

    AudioEngine(const AudioEngine&) = delete;
    AudioEngine& operator=(const AudioEngine&) = delete;
    AudioEngine(AudioEngine&&) = delete;
    AudioEngine& operator=(AudioEngine&&) = delete;

    // ========================================================================
    // INITIALIZATION
    // ========================================================================
    
    bool initialize();
    void shutdown();

    // ========================================================================
    // PLAYBACK CONTROL
    // ========================================================================
    
    bool loadAudio(const std::string& filePath, bool preload = false);
    bool play();
    bool pause();
    bool stop();
    bool seekTo(double positionSeconds);
    
    double getCurrentPosition() const;
    double getDuration() const;
    bool isPlaying() const;
    PlaybackState getState() const;

    // ========================================================================
    // BUFFERING STATE
    // ========================================================================
    
    double getBufferedPosition() const;
    double getRemainingDuration() const;
    double getPreloadProgress() const;
    bool isBuffering() const;

    // ========================================================================
    // VOLUME & AUDIO FOCUS
    // ========================================================================
    
    void setVolume(float volume);
    float getVolume() const;
    void duckVolume(float duckLevel, int fadeMs = 100);
    void restoreVolume(int fadeMs = 500);
    void onAudioFocusChange(AudioFocusState focusState);

    // ========================================================================
    // PLAYBACK SPEED
    // ========================================================================
    
    void setPlaybackSpeed(float speed);
    float getPlaybackSpeed() const;

    // ========================================================================
    // PRELOADING
    // ========================================================================
    
    bool preloadNext(const std::string& filePath);
    bool switchToPreloaded();
    void clearPreloadBuffer();

    // ========================================================================
    // NATIVE REPEAT LOOP
    // ========================================================================
    
    /**
     * Set repeat mode with deterministic timing
     * Loop logic runs natively to avoid Dart timer jitter
     */
    void setRepeatMode(RepeatMode mode, int32_t count = 1);
    
    /**
     * Set repeat range (for RANGE mode)
     */
    void setRepeatRange(int32_t startAyah, int32_t endAyah);
    
    /**
     * Set pause interval between repeat iterations
     */
    void setRepeatPauseInterval(int32_t intervalMs);
    
    /**
     * Get read-only repeat state (for Dart FFI mirror)
     */
    RepeatState getRepeatState() const;
    
    /**
     * Clear repeat state
     */
    void clearRepeat();
    
    /**
     * Advance to next Ayah in repeat range
     * Called internally when Ayah ends
     */
    void advanceRepeat();

    // ========================================================================
    // CALLBACKS
    // ========================================================================
    
    void setCallbacks(const PlaybackCallbacks& callbacks);

    // ========================================================================
    // OBOE CALLBACKS
    // ========================================================================
    
    oboe::DataCallbackResult onAudioReady(
        oboe::AudioStream* audioStream,
        void* audioData,
        int32_t numFrames) override;
    
    void onErrorAfterClose(
        oboe::AudioStream* audioStream,
        oboe::Result error) override;

private:
    // Stream
    std::shared_ptr<oboe::AudioStream> stream_;
    std::mutex streamMutex_;
    
    // State
    std::atomic<PlaybackState> state_{PlaybackState::IDLE};
    std::atomic<bool> isInitialized_{false};
    bool wasPlaying_{false};  // For resume after pause
    
    // Audio buffers
    std::vector<int16_t> audioBuffer_;
    std::vector<int16_t> preloadBuffer_;
    std::atomic<size_t> readPosition_{0};
    size_t totalSamples_{0};
    
    // Buffering state
    std::atomic<double> bufferedPosition_{0.0};
    std::atomic<double> preloadProgress_{0.0};
    std::atomic<bool> isBuffering_{false};
    
    // Audio properties
    int32_t sampleRate_{44100};
    int32_t channelCount_{2};
    std::atomic<double> durationSeconds_{0.0};
    
    // Volume
    std::atomic<float> volume_{1.0f};
    std::atomic<float> targetVolume_{1.0f};
    std::atomic<float> volumeBeforeDuck_{1.0f};
    
    // Speed
    std::atomic<float> playbackSpeed_{1.0f};
    
    // Audio focus
    AudioFocusState audioFocusState_{AudioFocusState::GAIN};
    double savedPosition_{0.0};
    
    // Repeat state (native management)
    RepeatState repeatState_;
    std::mutex repeatMutex_;
    
    // Callbacks
    PlaybackCallbacks callbacks_;
    std::mutex callbackMutex_;
    
    // File paths
    std::string currentFilePath_;
    std::string preloadFilePath_;
    
    // ========================================================================
    // PRIVATE METHODS
    // ========================================================================
    
    bool createStream();
    void closeStream();
    bool decodeAudioFile(const std::string& filePath, std::vector<int16_t>& buffer);
    
    // Get current timestamp in nanoseconds
    int64_t getNowNs() const;
    
    // Deterministic callback emissions
    void notifyPlaybackStarted();
    void notifyPlaybackPaused(double position);
    void notifyPlaybackResumed(double position);
    void notifyPlaybackStopped();
    void notifyBufferingChanged(bool isBuffering, double progress);
    void notifySeekCompleted(double position);
    void notifyPreloadCompleted(const std::string& filePath);
    void notifyAyahEnded();
    void notifyPosition();
    void notifyRepeatIteration(int iteration, int total);
    void notifyRepeatCompleted();
    void notifyError(const std::string& error);
    
    // Repeat loop handling
    void handleAyahEnd();
    void executeRepeatPause();
};

} // namespace quran

// ============================================================================
// FFI EXPORTS (C API for Dart)
// ============================================================================

extern "C" {

// Lifecycle
__attribute__((visibility("default")))
void* audio_engine_create();

__attribute__((visibility("default")))
void audio_engine_destroy(void* engine);

__attribute__((visibility("default")))
int audio_engine_initialize(void* engine);

__attribute__((visibility("default")))
void audio_engine_shutdown(void* engine);

// Playback
__attribute__((visibility("default")))
int audio_engine_load(void* engine, const char* filePath, int preload);

__attribute__((visibility("default")))
int audio_engine_play(void* engine);

__attribute__((visibility("default")))
int audio_engine_pause(void* engine);

__attribute__((visibility("default")))
int audio_engine_stop(void* engine);

__attribute__((visibility("default")))
int audio_engine_seek(void* engine, double positionSeconds);

// State
__attribute__((visibility("default")))
double audio_engine_get_position(void* engine);

__attribute__((visibility("default")))
double audio_engine_get_duration(void* engine);

__attribute__((visibility("default")))
int audio_engine_is_playing(void* engine);

__attribute__((visibility("default")))
int audio_engine_get_state(void* engine);

// Buffering state
__attribute__((visibility("default")))
double audio_engine_get_buffered_position(void* engine);

__attribute__((visibility("default")))
double audio_engine_get_remaining_duration(void* engine);

__attribute__((visibility("default")))
double audio_engine_get_preload_progress(void* engine);

__attribute__((visibility("default")))
int audio_engine_is_buffering(void* engine);

// Volume
__attribute__((visibility("default")))
void audio_engine_set_volume(void* engine, float volume);

__attribute__((visibility("default")))
float audio_engine_get_volume(void* engine);

__attribute__((visibility("default")))
void audio_engine_duck_volume(void* engine, float duckLevel, int fadeMs);

__attribute__((visibility("default")))
void audio_engine_restore_volume(void* engine, int fadeMs);

__attribute__((visibility("default")))
void audio_engine_on_audio_focus_change(void* engine, int focusState);

// Speed
__attribute__((visibility("default")))
void audio_engine_set_speed(void* engine, float speed);

__attribute__((visibility("default")))
float audio_engine_get_speed(void* engine);

// Preloading
__attribute__((visibility("default")))
int audio_engine_preload_next(void* engine, const char* filePath);

__attribute__((visibility("default")))
int audio_engine_switch_to_preloaded(void* engine);

__attribute__((visibility("default")))
void audio_engine_clear_preload(void* engine);

// Native Repeat Loop
__attribute__((visibility("default")))
void audio_engine_set_repeat_mode(void* engine, int mode, int count);

__attribute__((visibility("default")))
void audio_engine_set_repeat_range(void* engine, int startAyah, int endAyah);

__attribute__((visibility("default")))
void audio_engine_set_repeat_pause_interval(void* engine, int intervalMs);

__attribute__((visibility("default")))
void audio_engine_clear_repeat(void* engine);

// Repeat state getters (read-only mirror for Dart)
__attribute__((visibility("default")))
int audio_engine_get_repeat_mode(void* engine);

__attribute__((visibility("default")))
int audio_engine_get_repeat_iteration(void* engine);

__attribute__((visibility("default")))
int audio_engine_get_repeat_target(void* engine);

__attribute__((visibility("default")))
int audio_engine_is_repeat_active(void* engine);

// ============================================================================
// EXPANDED CALLBACKS (Deterministic Timestamps)
// ============================================================================

typedef void (*PlaybackStartedCallback)(int64_t timestampNs);
typedef void (*PlaybackPausedCallback)(int64_t timestampNs, double position);
typedef void (*PlaybackResumedCallback)(int64_t timestampNs, double position);
typedef void (*PlaybackStoppedCallback)(int64_t timestampNs);
typedef void (*BufferingChangedCallback)(int isBuffering, double progress);
typedef void (*SeekCompletedCallback)(int64_t timestampNs, double position);
typedef void (*PreloadCompletedCallback)(const char* filePath);
typedef void (*AyahEndedCallback)();
typedef void (*PositionChangedCallback)(double position);
typedef void (*RepeatIterationCallback)(int iteration, int total);
typedef void (*RepeatCompletedCallback)();
typedef void (*ErrorCallback)(const char* error);

__attribute__((visibility("default")))
void audio_engine_set_expanded_callbacks(
    void* engine,
    PlaybackStartedCallback onPlaybackStarted,
    PlaybackPausedCallback onPlaybackPaused,
    PlaybackResumedCallback onPlaybackResumed,
    PlaybackStoppedCallback onPlaybackStopped,
    BufferingChangedCallback onBufferingChanged,
    SeekCompletedCallback onSeekCompleted,
    PreloadCompletedCallback onPreloadCompleted,
    AyahEndedCallback onAyahEnded,
    PositionChangedCallback onPositionChanged,
    RepeatIterationCallback onRepeatIteration,
    RepeatCompletedCallback onRepeatCompleted,
    ErrorCallback onError
);

} // extern "C"

#endif // QURAN_AUDIO_ENGINE_H
