/**
 * audio_engine.cpp
 * 
 * C++ Native Audio Engine Implementation
 * Deterministic callbacks and native repeat loop
 */

#include "audio_engine.h"
#include <android/log.h>
#include <cmath>
#include <cstring>
#include <thread>

#define LOG_TAG "QuranAudioEngine"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN, LOG_TAG, __VA_ARGS__)

namespace quran {

// ============================================================================
// CONSTRUCTOR / DESTRUCTOR
// ============================================================================

AudioEngine::AudioEngine() {
    LOGI("AudioEngine created");
}

AudioEngine::~AudioEngine() {
    shutdown();
    LOGI("AudioEngine destroyed");
}

// ============================================================================
// TIMESTAMP HELPER
// ============================================================================

int64_t AudioEngine::getNowNs() const {
    auto now = std::chrono::high_resolution_clock::now();
    return std::chrono::duration_cast<std::chrono::nanoseconds>(
        now.time_since_epoch()
    ).count();
}

// ============================================================================
// INITIALIZATION
// ============================================================================

bool AudioEngine::initialize() {
    if (isInitialized_.load()) {
        LOGW("AudioEngine already initialized");
        return true;
    }
    
    LOGI("Initializing AudioEngine");
    isInitialized_.store(true);
    state_.store(PlaybackState::IDLE);
    
    return true;
}

void AudioEngine::shutdown() {
    if (!isInitialized_.load()) {
        return;
    }
    
    LOGI("Shutting down AudioEngine");
    closeStream();
    audioBuffer_.clear();
    preloadBuffer_.clear();
    clearRepeat();
    isInitialized_.store(false);
    state_.store(PlaybackState::IDLE);
}

// ============================================================================
// PLAYBACK CONTROL
// ============================================================================

bool AudioEngine::loadAudio(const std::string& filePath, bool preload) {
    LOGI("Loading audio: %s (preload=%d)", filePath.c_str(), preload);
    
    if (!isInitialized_.load()) {
        notifyError("Engine not initialized");
        return false;
    }
    
    state_.store(PlaybackState::LOADING);
    notifyBufferingChanged(true, 0.0);
    
    if (!decodeAudioFile(filePath, audioBuffer_)) {
        LOGE("Failed to decode audio file");
        notifyError("Failed to decode audio file");
        notifyBufferingChanged(false, 0.0);
        state_.store(PlaybackState::ERROR);
        return false;
    }
    
    currentFilePath_ = filePath;
    totalSamples_ = audioBuffer_.size();
    readPosition_.store(0);
    
    durationSeconds_.store(
        static_cast<double>(totalSamples_) / (sampleRate_ * channelCount_)
    );
    
    bufferedPosition_.store(durationSeconds_.load());
    notifyBufferingChanged(false, 1.0);
    
    LOGI("Audio loaded: %.2f seconds, %zu samples", 
         durationSeconds_.load(), totalSamples_);
    
    state_.store(PlaybackState::IDLE);
    return true;
}

bool AudioEngine::play() {
    if (!isInitialized_.load()) {
        LOGE("Engine not initialized");
        return false;
    }
    
    if (audioBuffer_.empty()) {
        notifyError("No audio loaded");
        return false;
    }
    
    PlaybackState currentState = state_.load();
    bool isResume = (currentState == PlaybackState::PAUSED);
    
    if (!stream_) {
        if (!createStream()) {
            notifyError("Failed to create audio stream");
            return false;
        }
    }
    
    oboe::Result result = stream_->requestStart();
    if (result != oboe::Result::OK) {
        LOGE("Failed to start stream: %s", oboe::convertToText(result));
        notifyError("Failed to start playback");
        return false;
    }
    
    state_.store(PlaybackState::PLAYING);
    
    if (isResume) {
        notifyPlaybackResumed(getCurrentPosition());
    } else {
        notifyPlaybackStarted();
    }
    
    LOGI("Playback %s", isResume ? "resumed" : "started");
    return true;
}

bool AudioEngine::pause() {
    if (!stream_) {
        return false;
    }
    
    double position = getCurrentPosition();
    wasPlaying_ = true;
    
    oboe::Result result = stream_->requestPause();
    if (result != oboe::Result::OK) {
        LOGE("Failed to pause stream: %s", oboe::convertToText(result));
        return false;
    }
    
    state_.store(PlaybackState::PAUSED);
    notifyPlaybackPaused(position);
    
    LOGI("Playback paused at %.2f", position);
    return true;
}

bool AudioEngine::stop() {
    double position = getCurrentPosition();
    
    if (stream_) {
        stream_->requestStop();
    }
    
    readPosition_.store(0);
    wasPlaying_ = false;
    state_.store(PlaybackState::STOPPED);
    notifyPlaybackStopped();
    
    LOGI("Playback stopped");
    return true;
}

bool AudioEngine::seekTo(double positionSeconds) {
    int64_t startNs = getNowNs();
    
    if (positionSeconds < 0 || positionSeconds > durationSeconds_.load()) {
        LOGW("Seek position out of range: %.2f", positionSeconds);
        return false;
    }
    
    size_t samplePosition = static_cast<size_t>(
        positionSeconds * sampleRate_ * channelCount_
    );
    samplePosition = (samplePosition / channelCount_) * channelCount_;
    
    if (samplePosition >= totalSamples_) {
        samplePosition = 0;
    }
    
    readPosition_.store(samplePosition);
    
    int64_t endNs = getNowNs();
    int64_t latencyUs = (endNs - startNs) / 1000;
    LOGI("Seek to %.2f completed in %lld us", positionSeconds, latencyUs);
    
    if (latencyUs > 10000) {
        LOGW("Seek latency exceeded 10ms target");
    }
    
    notifySeekCompleted(positionSeconds);
    return true;
}

double AudioEngine::getCurrentPosition() const {
    size_t pos = readPosition_.load();
    return static_cast<double>(pos) / (sampleRate_ * channelCount_);
}

double AudioEngine::getDuration() const {
    return durationSeconds_.load();
}

bool AudioEngine::isPlaying() const {
    return state_.load() == PlaybackState::PLAYING;
}

PlaybackState AudioEngine::getState() const {
    return state_.load();
}

// ============================================================================
// BUFFERING STATE
// ============================================================================

double AudioEngine::getBufferedPosition() const {
    return bufferedPosition_.load();
}

double AudioEngine::getRemainingDuration() const {
    return durationSeconds_.load() - getCurrentPosition();
}

double AudioEngine::getPreloadProgress() const {
    return preloadProgress_.load();
}

bool AudioEngine::isBuffering() const {
    return isBuffering_.load();
}

// ============================================================================
// VOLUME & AUDIO FOCUS
// ============================================================================

void AudioEngine::setVolume(float volume) {
    volume = std::clamp(volume, 0.0f, 1.0f);
    volume_.store(volume);
    targetVolume_.store(volume);
}

float AudioEngine::getVolume() const {
    return volume_.load();
}

void AudioEngine::duckVolume(float duckLevel, int /*fadeMs*/) {
    volumeBeforeDuck_.store(volume_.load());
    duckLevel = std::clamp(duckLevel, 0.0f, 1.0f);
    volume_.store(duckLevel);
    LOGI("Volume ducked to %.1f%%", duckLevel * 100);
}

void AudioEngine::restoreVolume(int /*fadeMs*/) {
    float restored = volumeBeforeDuck_.load();
    volume_.store(restored);
    LOGI("Volume restored to %.1f%%", restored * 100);
}

void AudioEngine::onAudioFocusChange(AudioFocusState focusState) {
    audioFocusState_ = focusState;
    
    switch (focusState) {
        case AudioFocusState::GAIN:
            LOGI("Audio focus gained");
            if (savedPosition_ > 0 && state_.load() == PlaybackState::PAUSED) {
                seekTo(savedPosition_);
                play();
                savedPosition_ = 0;
            }
            restoreVolume(500);
            break;
            
        case AudioFocusState::LOSS:
            LOGI("Audio focus lost");
            savedPosition_ = getCurrentPosition();
            pause();
            break;
            
        case AudioFocusState::LOSS_TRANSIENT:
            LOGI("Audio focus lost transient");
            savedPosition_ = getCurrentPosition();
            pause();
            break;
            
        case AudioFocusState::LOSS_TRANSIENT_CAN_DUCK:
            LOGI("Audio focus loss - ducking");
            duckVolume(0.3f, 100);
            break;
    }
}

// ============================================================================
// PLAYBACK SPEED
// ============================================================================

void AudioEngine::setPlaybackSpeed(float speed) {
    speed = std::clamp(speed, 0.5f, 2.0f);
    playbackSpeed_.store(speed);
    LOGI("Playback speed set to %.2fx", speed);
}

float AudioEngine::getPlaybackSpeed() const {
    return playbackSpeed_.load();
}

// ============================================================================
// PRELOADING
// ============================================================================

bool AudioEngine::preloadNext(const std::string& filePath) {
    LOGI("Preloading: %s", filePath.c_str());
    preloadProgress_.store(0.0);
    
    if (!decodeAudioFile(filePath, preloadBuffer_)) {
        LOGE("Failed to preload audio");
        return false;
    }
    
    preloadFilePath_ = filePath;
    preloadProgress_.store(1.0);
    
    LOGI("Preload complete: %zu samples", preloadBuffer_.size());
    notifyPreloadCompleted(filePath);
    return true;
}

bool AudioEngine::switchToPreloaded() {
    if (preloadBuffer_.empty()) {
        LOGE("No preloaded audio available");
        return false;
    }
    
    LOGI("Switching to preloaded buffer");
    
    std::swap(audioBuffer_, preloadBuffer_);
    currentFilePath_ = preloadFilePath_;
    totalSamples_ = audioBuffer_.size();
    readPosition_.store(0);
    
    durationSeconds_.store(
        static_cast<double>(totalSamples_) / (sampleRate_ * channelCount_)
    );
    bufferedPosition_.store(durationSeconds_.load());
    
    preloadBuffer_.clear();
    preloadFilePath_.clear();
    preloadProgress_.store(0.0);
    
    return true;
}

void AudioEngine::clearPreloadBuffer() {
    preloadBuffer_.clear();
    preloadFilePath_.clear();
    preloadProgress_.store(0.0);
    LOGI("Preload buffer cleared");
}

// ============================================================================
// NATIVE REPEAT LOOP
// ============================================================================

void AudioEngine::setRepeatMode(RepeatMode mode, int32_t count) {
    std::lock_guard<std::mutex> lock(repeatMutex_);
    
    repeatState_.mode = mode;
    repeatState_.targetIterations = count;
    repeatState_.iterationCount = 0;
    repeatState_.isActive = (mode != RepeatMode::NONE);
    
    LOGI("Repeat mode set: %d, count: %d", static_cast<int>(mode), count);
}

void AudioEngine::setRepeatRange(int32_t startAyah, int32_t endAyah) {
    std::lock_guard<std::mutex> lock(repeatMutex_);
    
    repeatState_.startAyah = startAyah;
    repeatState_.endAyah = endAyah;
    repeatState_.currentAyah = startAyah;
    
    LOGI("Repeat range set: %d to %d", startAyah, endAyah);
}

void AudioEngine::setRepeatPauseInterval(int32_t intervalMs) {
    std::lock_guard<std::mutex> lock(repeatMutex_);
    repeatState_.pauseIntervalMs = intervalMs;
    LOGI("Repeat pause interval: %d ms", intervalMs);
}

RepeatState AudioEngine::getRepeatState() const {
    std::lock_guard<std::mutex> lock(const_cast<std::mutex&>(repeatMutex_));
    return repeatState_;
}

void AudioEngine::clearRepeat() {
    std::lock_guard<std::mutex> lock(repeatMutex_);
    
    repeatState_.mode = RepeatMode::NONE;
    repeatState_.isActive = false;
    repeatState_.iterationCount = 0;
    repeatState_.currentAyah = 0;
    
    LOGI("Repeat cleared");
}

void AudioEngine::advanceRepeat() {
    std::lock_guard<std::mutex> lock(repeatMutex_);
    
    if (!repeatState_.isActive) return;
    
    switch (repeatState_.mode) {
        case RepeatMode::SINGLE:
            repeatState_.iterationCount++;
            notifyRepeatIteration(repeatState_.iterationCount, 
                                  repeatState_.targetIterations);
            break;
            
        case RepeatMode::RANGE:
            if (repeatState_.currentAyah < repeatState_.endAyah) {
                repeatState_.currentAyah++;
            } else {
                repeatState_.currentAyah = repeatState_.startAyah;
                repeatState_.iterationCount++;
            }
            notifyRepeatIteration(repeatState_.iterationCount,
                                  repeatState_.targetIterations);
            break;
            
        case RepeatMode::INFINITE:
            repeatState_.iterationCount++;
            notifyRepeatIteration(repeatState_.iterationCount, -1);
            break;
            
        case RepeatMode::COUNT:
            repeatState_.iterationCount++;
            if (repeatState_.iterationCount >= repeatState_.targetIterations) {
                repeatState_.isActive = false;
                notifyRepeatCompleted();
            } else {
                notifyRepeatIteration(repeatState_.iterationCount,
                                      repeatState_.targetIterations);
            }
            break;
            
        case RepeatMode::NONE:
            break;
    }
    
    repeatState_.lastIterationTimestampNs = getNowNs();
}

void AudioEngine::handleAyahEnd() {
    notifyAyahEnded();
    
    std::lock_guard<std::mutex> lock(repeatMutex_);
    if (!repeatState_.isActive) return;
    
    if (repeatState_.pauseIntervalMs > 0) {
        executeRepeatPause();
    }
    
    advanceRepeat();
    
    if (repeatState_.isActive) {
        readPosition_.store(0);
        play();
    }
}

void AudioEngine::executeRepeatPause() {
    repeatState_.pauseStartTimestampNs = getNowNs();
    
    // Pause for interval (run on separate thread to not block audio)
    std::this_thread::sleep_for(
        std::chrono::milliseconds(repeatState_.pauseIntervalMs)
    );
}

// ============================================================================
// CALLBACKS
// ============================================================================

void AudioEngine::setCallbacks(const PlaybackCallbacks& callbacks) {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    callbacks_ = callbacks;
}

void AudioEngine::notifyPlaybackStarted() {
    int64_t ts = getNowNs();
    LOGI("Callback: PlaybackStarted @%lld ns", ts);
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onPlaybackStarted) {
        callbacks_.onPlaybackStarted(ts);
    }
}

void AudioEngine::notifyPlaybackPaused(double position) {
    int64_t ts = getNowNs();
    LOGI("Callback: PlaybackPaused @%lld ns, pos=%.2f", ts, position);
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onPlaybackPaused) {
        callbacks_.onPlaybackPaused(ts, position);
    }
}

void AudioEngine::notifyPlaybackResumed(double position) {
    int64_t ts = getNowNs();
    LOGI("Callback: PlaybackResumed @%lld ns, pos=%.2f", ts, position);
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onPlaybackResumed) {
        callbacks_.onPlaybackResumed(ts, position);
    }
}

void AudioEngine::notifyPlaybackStopped() {
    int64_t ts = getNowNs();
    LOGI("Callback: PlaybackStopped @%lld ns", ts);
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onPlaybackStopped) {
        callbacks_.onPlaybackStopped(ts);
    }
}

void AudioEngine::notifyBufferingChanged(bool buffering, double progress) {
    isBuffering_.store(buffering);
    LOGI("Callback: BufferingChanged buffering=%d, progress=%.2f", buffering, progress);
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onBufferingChanged) {
        callbacks_.onBufferingChanged(buffering, progress);
    }
}

void AudioEngine::notifySeekCompleted(double position) {
    int64_t ts = getNowNs();
    LOGI("Callback: SeekCompleted @%lld ns, pos=%.2f", ts, position);
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onSeekCompleted) {
        callbacks_.onSeekCompleted(ts, position);
    }
}

void AudioEngine::notifyPreloadCompleted(const std::string& filePath) {
    LOGI("Callback: PreloadCompleted %s", filePath.c_str());
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onPreloadCompleted) {
        callbacks_.onPreloadCompleted(filePath);
    }
}

void AudioEngine::notifyAyahEnded() {
    LOGI("Callback: AyahEnded");
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onAyahEnded) {
        callbacks_.onAyahEnded();
    }
}

void AudioEngine::notifyPosition() {
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onPositionChanged) {
        callbacks_.onPositionChanged(getCurrentPosition());
    }
}

void AudioEngine::notifyRepeatIteration(int iteration, int total) {
    LOGI("Callback: RepeatIteration %d/%d", iteration, total);
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onRepeatIteration) {
        callbacks_.onRepeatIteration(iteration, total);
    }
}

void AudioEngine::notifyRepeatCompleted() {
    LOGI("Callback: RepeatCompleted");
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onRepeatCompleted) {
        callbacks_.onRepeatCompleted();
    }
}

void AudioEngine::notifyError(const std::string& error) {
    LOGE("Callback: Error - %s", error.c_str());
    
    std::lock_guard<std::mutex> lock(callbackMutex_);
    if (callbacks_.onError) {
        callbacks_.onError(error);
    }
}

// ============================================================================
// OBOE CALLBACKS
// ============================================================================

oboe::DataCallbackResult AudioEngine::onAudioReady(
    oboe::AudioStream* /*audioStream*/,
    void* audioData,
    int32_t numFrames) {
    
    auto* outputBuffer = static_cast<int16_t*>(audioData);
    size_t numSamples = numFrames * channelCount_;
    size_t currentPos = readPosition_.load();
    float vol = volume_.load();
    
    if (currentPos >= totalSamples_) {
        std::memset(outputBuffer, 0, numSamples * sizeof(int16_t));
        handleAyahEnd();
        return oboe::DataCallbackResult::Stop;
    }
    
    size_t samplesToWrite = std::min(numSamples, totalSamples_ - currentPos);
    
    for (size_t i = 0; i < samplesToWrite; ++i) {
        outputBuffer[i] = static_cast<int16_t>(audioBuffer_[currentPos + i] * vol);
    }
    
    if (samplesToWrite < numSamples) {
        std::memset(outputBuffer + samplesToWrite, 0, 
                   (numSamples - samplesToWrite) * sizeof(int16_t));
    }
    
    readPosition_.store(currentPos + samplesToWrite);
    
    static int callCount = 0;
    if (++callCount % 10 == 0) {
        notifyPosition();
    }
    
    return oboe::DataCallbackResult::Continue;
}

void AudioEngine::onErrorAfterClose(
    oboe::AudioStream* /*audioStream*/,
    oboe::Result error) {
    
    LOGE("Oboe stream error: %s", oboe::convertToText(error));
    notifyError("Audio stream error");
    state_.store(PlaybackState::ERROR);
}

// ============================================================================
// PRIVATE METHODS
// ============================================================================

bool AudioEngine::createStream() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    
    oboe::AudioStreamBuilder builder;
    builder.setDirection(oboe::Direction::Output)
           .setPerformanceMode(oboe::PerformanceMode::LowLatency)
           .setSharingMode(oboe::SharingMode::Exclusive)
           .setFormat(oboe::AudioFormat::I16)
           .setChannelCount(channelCount_)
           .setSampleRate(sampleRate_)
           .setDataCallback(this)
           .setErrorCallback(this);
    
    oboe::Result result = builder.openStream(stream_);
    if (result != oboe::Result::OK) {
        LOGE("Failed to open stream: %s", oboe::convertToText(result));
        return false;
    }
    
    LOGI("Stream opened: %d Hz, %d channels, buffer: %d frames",
         stream_->getSampleRate(),
         stream_->getChannelCount(),
         stream_->getBufferSizeInFrames());
    
    return true;
}

void AudioEngine::closeStream() {
    std::lock_guard<std::mutex> lock(streamMutex_);
    
    if (stream_) {
        stream_->stop();
        stream_->close();
        stream_.reset();
        LOGI("Stream closed");
    }
}

bool AudioEngine::decodeAudioFile(
    const std::string& filePath, 
    std::vector<int16_t>& buffer) {
    
    LOGI("Decoding file: %s", filePath.c_str());
    
    // TODO: Implement MP3 decoding via MediaCodec
    // Placeholder: generate 1 second of silence for testing
    size_t testSamples = sampleRate_ * channelCount_;
    buffer.resize(testSamples, 0);
    
    return true;
}

} // namespace quran

// ============================================================================
// FFI EXPORTS IMPLEMENTATION
// ============================================================================

extern "C" {

void* audio_engine_create() {
    return new quran::AudioEngine();
}

void audio_engine_destroy(void* engine) {
    delete static_cast<quran::AudioEngine*>(engine);
}

int audio_engine_initialize(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->initialize() ? 1 : 0;
}

void audio_engine_shutdown(void* engine) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->shutdown();
    }
}

int audio_engine_load(void* engine, const char* filePath, int preload) {
    if (!engine || !filePath) return 0;
    return static_cast<quran::AudioEngine*>(engine)->loadAudio(
        std::string(filePath), preload != 0
    ) ? 1 : 0;
}

int audio_engine_play(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->play() ? 1 : 0;
}

int audio_engine_pause(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->pause() ? 1 : 0;
}

int audio_engine_stop(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->stop() ? 1 : 0;
}

int audio_engine_seek(void* engine, double positionSeconds) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->seekTo(positionSeconds) ? 1 : 0;
}

double audio_engine_get_position(void* engine) {
    if (!engine) return 0.0;
    return static_cast<quran::AudioEngine*>(engine)->getCurrentPosition();
}

double audio_engine_get_duration(void* engine) {
    if (!engine) return 0.0;
    return static_cast<quran::AudioEngine*>(engine)->getDuration();
}

int audio_engine_is_playing(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->isPlaying() ? 1 : 0;
}

int audio_engine_get_state(void* engine) {
    if (!engine) return 0;
    return static_cast<int>(static_cast<quran::AudioEngine*>(engine)->getState());
}

// Buffering state
double audio_engine_get_buffered_position(void* engine) {
    if (!engine) return 0.0;
    return static_cast<quran::AudioEngine*>(engine)->getBufferedPosition();
}

double audio_engine_get_remaining_duration(void* engine) {
    if (!engine) return 0.0;
    return static_cast<quran::AudioEngine*>(engine)->getRemainingDuration();
}

double audio_engine_get_preload_progress(void* engine) {
    if (!engine) return 0.0;
    return static_cast<quran::AudioEngine*>(engine)->getPreloadProgress();
}

int audio_engine_is_buffering(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->isBuffering() ? 1 : 0;
}

// Volume
void audio_engine_set_volume(void* engine, float volume) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->setVolume(volume);
    }
}

float audio_engine_get_volume(void* engine) {
    if (!engine) return 0.0f;
    return static_cast<quran::AudioEngine*>(engine)->getVolume();
}

void audio_engine_duck_volume(void* engine, float duckLevel, int fadeMs) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->duckVolume(duckLevel, fadeMs);
    }
}

void audio_engine_restore_volume(void* engine, int fadeMs) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->restoreVolume(fadeMs);
    }
}

void audio_engine_on_audio_focus_change(void* engine, int focusState) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->onAudioFocusChange(
            static_cast<quran::AudioFocusState>(focusState)
        );
    }
}

// Speed
void audio_engine_set_speed(void* engine, float speed) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->setPlaybackSpeed(speed);
    }
}

float audio_engine_get_speed(void* engine) {
    if (!engine) return 1.0f;
    return static_cast<quran::AudioEngine*>(engine)->getPlaybackSpeed();
}

// Preloading
int audio_engine_preload_next(void* engine, const char* filePath) {
    if (!engine || !filePath) return 0;
    return static_cast<quran::AudioEngine*>(engine)->preloadNext(
        std::string(filePath)
    ) ? 1 : 0;
}

int audio_engine_switch_to_preloaded(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->switchToPreloaded() ? 1 : 0;
}

void audio_engine_clear_preload(void* engine) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->clearPreloadBuffer();
    }
}

// Native repeat loop
void audio_engine_set_repeat_mode(void* engine, int mode, int count) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->setRepeatMode(
            static_cast<quran::RepeatMode>(mode), count
        );
    }
}

void audio_engine_set_repeat_range(void* engine, int startAyah, int endAyah) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->setRepeatRange(startAyah, endAyah);
    }
}

void audio_engine_set_repeat_pause_interval(void* engine, int intervalMs) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->setRepeatPauseInterval(intervalMs);
    }
}

void audio_engine_clear_repeat(void* engine) {
    if (engine) {
        static_cast<quran::AudioEngine*>(engine)->clearRepeat();
    }
}

int audio_engine_get_repeat_mode(void* engine) {
    if (!engine) return 0;
    return static_cast<int>(
        static_cast<quran::AudioEngine*>(engine)->getRepeatState().mode
    );
}

int audio_engine_get_repeat_iteration(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->getRepeatState().iterationCount;
}

int audio_engine_get_repeat_target(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->getRepeatState().targetIterations;
}

int audio_engine_is_repeat_active(void* engine) {
    if (!engine) return 0;
    return static_cast<quran::AudioEngine*>(engine)->getRepeatState().isActive ? 1 : 0;
}

// Expanded callbacks
static PlaybackStartedCallback g_playbackStartedCallback = nullptr;
static PlaybackPausedCallback g_playbackPausedCallback = nullptr;
static PlaybackResumedCallback g_playbackResumedCallback = nullptr;
static PlaybackStoppedCallback g_playbackStoppedCallback = nullptr;
static BufferingChangedCallback g_bufferingChangedCallback = nullptr;
static SeekCompletedCallback g_seekCompletedCallback = nullptr;
static PreloadCompletedCallback g_preloadCompletedCallback = nullptr;
static AyahEndedCallback g_ayahEndedCallback = nullptr;
static PositionChangedCallback g_positionChangedCallback = nullptr;
static RepeatIterationCallback g_repeatIterationCallback = nullptr;
static RepeatCompletedCallback g_repeatCompletedCallback = nullptr;
static ErrorCallback g_errorCallback = nullptr;

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
) {
    if (!engine) return;
    
    g_playbackStartedCallback = onPlaybackStarted;
    g_playbackPausedCallback = onPlaybackPaused;
    g_playbackResumedCallback = onPlaybackResumed;
    g_playbackStoppedCallback = onPlaybackStopped;
    g_bufferingChangedCallback = onBufferingChanged;
    g_seekCompletedCallback = onSeekCompleted;
    g_preloadCompletedCallback = onPreloadCompleted;
    g_ayahEndedCallback = onAyahEnded;
    g_positionChangedCallback = onPositionChanged;
    g_repeatIterationCallback = onRepeatIteration;
    g_repeatCompletedCallback = onRepeatCompleted;
    g_errorCallback = onError;
    
    quran::PlaybackCallbacks callbacks;
    
    callbacks.onPlaybackStarted = [](int64_t ts) {
        if (g_playbackStartedCallback) g_playbackStartedCallback(ts);
    };
    
    callbacks.onPlaybackPaused = [](int64_t ts, double pos) {
        if (g_playbackPausedCallback) g_playbackPausedCallback(ts, pos);
    };
    
    callbacks.onPlaybackResumed = [](int64_t ts, double pos) {
        if (g_playbackResumedCallback) g_playbackResumedCallback(ts, pos);
    };
    
    callbacks.onPlaybackStopped = [](int64_t ts) {
        if (g_playbackStoppedCallback) g_playbackStoppedCallback(ts);
    };
    
    callbacks.onBufferingChanged = [](bool isBuffering, double progress) {
        if (g_bufferingChangedCallback) {
            g_bufferingChangedCallback(isBuffering ? 1 : 0, progress);
        }
    };
    
    callbacks.onSeekCompleted = [](int64_t ts, double pos) {
        if (g_seekCompletedCallback) g_seekCompletedCallback(ts, pos);
    };
    
    callbacks.onPreloadCompleted = [](const std::string& path) {
        if (g_preloadCompletedCallback) g_preloadCompletedCallback(path.c_str());
    };
    
    callbacks.onAyahEnded = []() {
        if (g_ayahEndedCallback) g_ayahEndedCallback();
    };
    
    callbacks.onPositionChanged = [](double pos) {
        if (g_positionChangedCallback) g_positionChangedCallback(pos);
    };
    
    callbacks.onRepeatIteration = [](int iteration, int total) {
        if (g_repeatIterationCallback) g_repeatIterationCallback(iteration, total);
    };
    
    callbacks.onRepeatCompleted = []() {
        if (g_repeatCompletedCallback) g_repeatCompletedCallback();
    };
    
    callbacks.onError = [](const std::string& error) {
        if (g_errorCallback) g_errorCallback(error.c_str());
    };
    
    static_cast<quran::AudioEngine*>(engine)->setCallbacks(callbacks);
}

} // extern "C"
