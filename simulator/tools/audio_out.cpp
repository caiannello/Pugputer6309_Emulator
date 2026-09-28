#include "audio_out.hpp"

#include <algorithm>
#include <cstdio>
#include <cstring>
#include <vector>

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <mmsystem.h>
#else
#include <csignal>
#include <cstdlib>
#endif

#ifdef _WIN32
// A ring of waveOut buffers: the one being filled, the rest queued or played. write()
// waits for the next one to come back from the device when all are out.
struct AudioOut::Impl {
    static constexpr int kBuffers = 6;
    static constexpr size_t kFrames = 2048; // ~43ms each at 48kHz: ~0.26s queued at most
    HWAVEOUT dev = nullptr;
    HANDLE done = nullptr; // signalled whenever the device finishes a buffer
    WAVEHDR hdr[kBuffers] = {};
    std::vector<int16_t> data[kBuffers];
    int cur = 0;      // the buffer being filled
    size_t fill = 0;  // frames in it so far

    ~Impl() {
        if (dev) {
            send();
            for (int i = 0; i < kBuffers; ++i)
                while (hdr[i].dwFlags & WHDR_PREPARED && !(hdr[i].dwFlags & WHDR_DONE)) WaitForSingleObject(done, 50);
            waveOutReset(dev);
            for (int i = 0; i < kBuffers; ++i)
                if (hdr[i].dwFlags & WHDR_PREPARED) waveOutUnprepareHeader(dev, &hdr[i], sizeof(WAVEHDR));
            waveOutClose(dev);
        }
        if (done) CloseHandle(done);
    }
    // Waits until buffer `i` isn't with the device.
    void wait_free(int i) {
        while ((hdr[i].dwFlags & WHDR_PREPARED) && !(hdr[i].dwFlags & WHDR_DONE)) WaitForSingleObject(done, 20);
        if (hdr[i].dwFlags & WHDR_PREPARED) waveOutUnprepareHeader(dev, &hdr[i], sizeof(WAVEHDR));
    }
    // Queues the current buffer (if it has anything) and moves on to the next.
    void send() {
        if (fill == 0) return;
        WAVEHDR& h = hdr[cur];
        h = WAVEHDR{};
        h.lpData = reinterpret_cast<LPSTR>(data[cur].data());
        h.dwBufferLength = static_cast<DWORD>(fill * 4);
        waveOutPrepareHeader(dev, &h, sizeof(WAVEHDR));
        waveOutWrite(dev, &h, sizeof(WAVEHDR));
        cur = (cur + 1) % kBuffers;
        fill = 0;
        wait_free(cur);
    }
};

AudioOut::AudioOut() : impl_(new Impl()) {}
AudioOut::~AudioOut() { close(); }

bool AudioOut::open(uint32_t rate) {
    close();
    impl_.reset(new Impl());
    WAVEFORMATEX fmt = {};
    fmt.wFormatTag = WAVE_FORMAT_PCM;
    fmt.nChannels = 2;
    fmt.nSamplesPerSec = rate;
    fmt.wBitsPerSample = 16;
    fmt.nBlockAlign = 4;
    fmt.nAvgBytesPerSec = rate * 4;
    impl_->done = CreateEventA(nullptr, FALSE, FALSE, nullptr);
    MMRESULT r = waveOutOpen(&impl_->dev, WAVE_MAPPER, &fmt, reinterpret_cast<DWORD_PTR>(impl_->done), 0,
                             CALLBACK_EVENT);
    if (r != MMSYSERR_NOERROR) {
        impl_->dev = nullptr;
        error_ = "no sound device (waveOutOpen failed)";
        return false;
    }
    for (auto& d : impl_->data) d.assign(Impl::kFrames * 2, 0);
    description_ = "the Windows sound device, " + std::to_string(rate) + " Hz";
    return true;
}

void AudioOut::close() { impl_.reset(new Impl()); }

void AudioOut::write(const int16_t* frames, size_t count) {
    Impl& m = *impl_;
    if (!m.dev) return;
    while (count > 0) {
        size_t k = std::min(count, Impl::kFrames - m.fill);
        std::memcpy(m.data[m.cur].data() + m.fill * 2, frames, k * 4);
        m.fill += k;
        frames += k * 2;
        count -= k;
        if (m.fill == Impl::kFrames) m.send();
    }
}

void AudioOut::idle() {
    if (impl_->dev) impl_->send();
}

#else // !_WIN32

// A pipe to a command-line player. The pipe (and the player's own buffer, kept small)
// fill up, and then write() blocks until the sound has played.
struct AudioOut::Impl {
    FILE* pipe = nullptr;
    ~Impl() {
        if (pipe) pclose(pipe);
    }
};

namespace {
bool have_program(const char* name) {
    std::string cmd = std::string("command -v ") + name + " >/dev/null 2>&1";
    return std::system(cmd.c_str()) == 0;
}
} // namespace

AudioOut::AudioOut() : impl_(new Impl()) {}
AudioOut::~AudioOut() { close(); }

bool AudioOut::open(uint32_t rate) {
    close();
    std::signal(SIGPIPE, SIG_IGN); // a player that quits must not take the emulator with it
    std::string r = std::to_string(rate);
    struct Player {
        const char* name;
        std::string cmd;
    };
    const Player players[] = {
        {"aplay", "aplay -q -t raw -f S16_LE -c 2 -r " + r + " --buffer-time=200000 - 2>/dev/null"},
        {"pacat", "pacat --raw --format=s16le --channels=2 --rate=" + r + " --latency-msec=150 2>/dev/null"},
        {"pw-cat", "pw-cat --playback --format=s16 --channels=2 --rate=" + r + " - 2>/dev/null"},
    };
    for (const Player& p : players) {
        if (!have_program(p.name)) continue;
        FILE* f = popen(p.cmd.c_str(), "w");
        if (!f) continue;
        setvbuf(f, nullptr, _IOFBF, 8192);
        impl_->pipe = f;
        description_ = std::string(p.name) + ", " + r + " Hz";
        return true;
    }
    error_ = "no sound player found (install alsa-utils for aplay, or pulseaudio-utils for pacat)";
    return false;
}

void AudioOut::close() { impl_.reset(new Impl()); }

void AudioOut::write(const int16_t* frames, size_t count) {
    if (!impl_->pipe) return;
    if (std::fwrite(frames, 4, count, impl_->pipe) != count) { // the player has gone
        pclose(impl_->pipe);
        impl_->pipe = nullptr;
    }
}

void AudioOut::idle() {
    if (impl_->pipe) std::fflush(impl_->pipe);
}

#endif
