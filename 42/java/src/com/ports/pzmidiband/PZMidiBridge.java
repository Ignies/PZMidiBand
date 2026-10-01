package com.ports.pzmidiband;

import java.io.File;
import java.util.ArrayList;
import java.util.Arrays;

import javax.sound.midi.MidiChannel;
import javax.sound.midi.MidiEvent;
import javax.sound.midi.MidiMessage;
import javax.sound.midi.MidiSystem;
import javax.sound.midi.MetaMessage;
import javax.sound.midi.Sequence;
import javax.sound.midi.ShortMessage;
import javax.sound.midi.Soundbank;
import javax.sound.midi.Synthesizer;
import javax.sound.midi.Track;

import me.zed_0xff.zombie_buddy.Exposer;

/**
 * Lua-callable bridge for PZMidiBand mod.
 *
 * Discovered by ZombieBuddy via @Exposer.LuaClass and registered with PZ's
 * LuaJavaClassExposer. After exposure, Lua can reach this class either as the
 * global `PZMidiBridge` (PZ exposes by simple name) or via
 * `Packages.com.ports.pzmidiband.PZMidiBridge`.
 */
@Exposer.LuaClass
public final class PZMidiBridge {

    private static Synthesizer synth;
    private static Soundbank   currentBank;
    private static String      lastError = "";

    private static long[] evTimesMicros;
    private static int[]  evType;     // 1=NoteOn 2=NoteOff 3=PgmChg 4=CC 5=PitchBend 6=AllNotesOff 7=Tempo
    private static int[]  evCh;
    private static int[]  evD1;
    private static int[]  evD2;
    private static int    evCount;
    private static long   totalMicros;
    private static int[]  initialProgramPerChannel = new int[16];

    private PZMidiBridge() {}

    // ---------------------- Filesystem helpers ----------------------

    public static String getUserHome() {
        String h = System.getProperty("user.home");
        return h == null ? "" : h;
    }

    public static String getZomboidDir() {
        String h = getUserHome();
        return h.isEmpty() ? "" : (h + File.separator + "Zomboid");
    }

    public static boolean fileExists(String path) {
        if (path == null) return false;
        return new File(path).exists();
    }

    public static boolean mkdirs(String path) {
        if (path == null) return false;
        File f = new File(path);
        if (f.exists()) return true;
        return f.mkdirs();
    }

    /** Returns a flat array: [name1, "D"|"F", name2, "D"|"F", ...] for Lua. */
    public static Object[] listDir(String path) {
        if (path == null) return new Object[0];
        File d = new File(path);
        if (!d.exists() || !d.isDirectory()) return new Object[0];
        File[] files = d.listFiles();
        if (files == null) return new Object[0];
        Arrays.sort(files, (a, b) -> a.getName().compareToIgnoreCase(b.getName()));
        ArrayList<Object> out = new ArrayList<>(files.length * 2);
        for (File f : files) {
            out.add(f.getName());
            out.add(f.isDirectory() ? "D" : "F");
        }
        return out.toArray();
    }

    public static String parentDir(String path) {
        if (path == null) return "";
        File f = new File(path);
        File p = f.getParentFile();
        return p == null ? "" : p.getAbsolutePath();
    }

    // ---------------------- Synth lifecycle ----------------------

    public static String getLastError() { return lastError; }

    public static boolean openSynth(String soundfontPath) {
        try {
            if (synth == null) {
                synth = MidiSystem.getSynthesizer();
                synth.open();
            }
            if (soundfontPath != null && !soundfontPath.isEmpty()) {
                File sf = new File(soundfontPath);
                if (sf.exists()) {
                    Soundbank bank = MidiSystem.getSoundbank(sf);
                    if (bank != null && synth.isSoundbankSupported(bank)) {
                        if (currentBank != null) synth.unloadAllInstruments(currentBank);
                        synth.loadAllInstruments(bank);
                        currentBank = bank;
                    }
                }
            }
            return true;
        } catch (Throwable t) {
            lastError = t.getClass().getSimpleName() + ": " + t.getMessage();
            return false;
        }
    }

    public static void closeSynth() {
        try {
            if (synth != null) {
                allNotesOffAll();
                synth.close();
                synth = null;
                currentBank = null;
            }
        } catch (Throwable ignored) {}
    }

    public static boolean isSynthOpen() { return synth != null && synth.isOpen(); }

    public static String getSynthName() {
        if (synth == null) return "(none)";
        try { return synth.getDeviceInfo().getName(); } catch (Throwable t) { return "(unknown)"; }
    }

    private static MidiChannel ch(int channel) {
        if (synth == null) return null;
        MidiChannel[] chans = synth.getChannels();
        if (chans == null || channel < 0 || channel >= chans.length) return null;
        return chans[channel];
    }

    // ---------------------- Realtime MIDI ops ----------------------

    public static void noteOn(int channel, int key, int velocity) {
        MidiChannel c = ch(channel);
        if (c != null) c.noteOn(key & 0x7F, velocity & 0x7F);
    }

    public static void noteOff(int channel, int key) {
        MidiChannel c = ch(channel);
        if (c != null) c.noteOff(key & 0x7F);
    }

    public static void programChange(int channel, int program) {
        MidiChannel c = ch(channel);
        if (c != null) c.programChange(program & 0x7F);
    }

    public static void controlChange(int channel, int controller, int value) {
        MidiChannel c = ch(channel);
        if (c != null) c.controlChange(controller & 0x7F, value & 0x7F);
    }

    public static void pitchBend(int channel, int value14bit) {
        MidiChannel c = ch(channel);
        if (c != null) c.setPitchBend(value14bit & 0x3FFF);
    }

    public static void allNotesOff(int channel) {
        MidiChannel c = ch(channel);
        if (c != null) c.allNotesOff();
    }

    public static void allNotesOffAll() {
        if (synth == null) return;
        MidiChannel[] chans = synth.getChannels();
        if (chans == null) return;
        for (MidiChannel c : chans) if (c != null) c.allNotesOff();
    }

    /** 0..1 linear master volume, applied as CC7 on every channel. */
    public static void setMasterVolume(double gain) {
        if (synth == null) return;
        int v = (int) Math.max(0, Math.min(127, Math.round(gain * 127.0)));
        MidiChannel[] chans = synth.getChannels();
        if (chans == null) return;
        for (MidiChannel c : chans) if (c != null) c.controlChange(7, v);
    }

    // ---------------------- MIDI file parsing ----------------------

    public static int loadMidiFile(String path, int maxEvents, int maxTracks, long maxBytes) {
        try {
            File f = new File(path);
            if (!f.exists()) { lastError = "file not found: " + path; return -1; }
            if (f.length() > maxBytes) { lastError = "file too large"; return -1; }
            Sequence seq = MidiSystem.getSequence(f);
            if (seq.getDivisionType() != Sequence.PPQ) {
                lastError = "SMPTE division not supported";
                return -1;
            }
            Track[] tracks = seq.getTracks();
            if (tracks.length > maxTracks) { lastError = "too many tracks"; return -1; }

            int ppq = seq.getResolution();
            int estimate = 0;
            for (Track t : tracks) estimate += t.size();
            if (estimate > maxEvents) { lastError = "too many events"; return -1; }

            long[]  ticks    = new long[estimate];
            int[]   types    = new int[estimate];
            int[]   channels = new int[estimate];
            int[]   d1s      = new int[estimate];
            int[]   d2s      = new int[estimate];

            ArrayList<long[]> tempoMap = new ArrayList<>();
            tempoMap.add(new long[]{0L, 500000L});

            int out = 0;
            Arrays.fill(initialProgramPerChannel, 0);
            boolean[] seenProgram = new boolean[16];

            for (Track tr : tracks) {
                for (int i = 0; i < tr.size(); i++) {
                    MidiEvent me = tr.get(i);
                    MidiMessage msg = me.getMessage();
                    long tick = me.getTick();
                    if (msg instanceof ShortMessage) {
                        ShortMessage sm = (ShortMessage) msg;
                        int cmd = sm.getCommand();
                        int chn = sm.getChannel();
                        int data1 = sm.getData1();
                        int data2 = sm.getData2();
                        int type = 0;
                        switch (cmd) {
                            case ShortMessage.NOTE_ON:
                                type = (data2 == 0) ? 2 : 1; break;
                            case ShortMessage.NOTE_OFF:
                                type = 2; break;
                            case ShortMessage.PROGRAM_CHANGE:
                                type = 3;
                                if (!seenProgram[chn]) {
                                    initialProgramPerChannel[chn] = data1;
                                    seenProgram[chn] = true;
                                }
                                break;
                            case ShortMessage.CONTROL_CHANGE: type = 4; break;
                            case ShortMessage.PITCH_BEND: {
                                type = 5;
                                data1 = (data2 << 7) | data1;
                                data2 = 0;
                                break;
                            }
                            default: type = 0;
                        }
                        if (type != 0) {
                            ticks[out] = tick;
                            types[out] = type;
                            channels[out] = chn;
                            d1s[out] = data1;
                            d2s[out] = data2;
                            out++;
                        }
                    } else if (msg instanceof MetaMessage) {
                        MetaMessage mm = (MetaMessage) msg;
                        if (mm.getType() == 0x51) {
                            byte[] data = mm.getData();
                            if (data.length >= 3) {
                                long micros = ((data[0] & 0xFF) << 16)
                                            | ((data[1] & 0xFF) << 8)
                                            |  (data[2] & 0xFF);
                                tempoMap.add(new long[]{tick, micros});
                                ticks[out] = tick;
                                types[out] = 7;
                                channels[out] = 0;
                                d1s[out] = (int) (micros & 0x7FFFFFFFL);
                                d2s[out] = 0;
                                out++;
                            }
                        }
                    }
                }
            }

            // Sort indices by tick (stable)
            Integer[] idx = new Integer[out];
            for (int i = 0; i < out; i++) idx[i] = i;
            final long[] ticksRef = ticks;
            Arrays.sort(idx, (a, b) -> Long.compare(ticksRef[a], ticksRef[b]));

            tempoMap.sort((a, b) -> Long.compare(a[0], b[0]));
            long[] outTimes = new long[out];
            long curTempo = tempoMap.get(0)[1];
            long lastTick = 0;
            long accMicros = 0;
            int  tempoIdx = 1;
            for (int i = 0; i < out; i++) {
                long tick = ticks[idx[i]];
                while (tempoIdx < tempoMap.size() && tempoMap.get(tempoIdx)[0] <= tick) {
                    long changeTick = tempoMap.get(tempoIdx)[0];
                    accMicros += (changeTick - lastTick) * curTempo / ppq;
                    lastTick = changeTick;
                    curTempo = tempoMap.get(tempoIdx)[1];
                    tempoIdx++;
                }
                accMicros += (tick - lastTick) * curTempo / ppq;
                lastTick = tick;
                outTimes[i] = accMicros;
            }

            evTimesMicros = new long[out];
            evType = new int[out];
            evCh   = new int[out];
            evD1   = new int[out];
            evD2   = new int[out];
            for (int i = 0; i < out; i++) {
                int s = idx[i];
                evTimesMicros[i] = outTimes[i];
                evType[i] = types[s];
                evCh[i]   = channels[s];
                evD1[i]   = d1s[s];
                evD2[i]   = d2s[s];
            }
            evCount = out;
            totalMicros = out > 0 ? evTimesMicros[out - 1] : 0;
            lastError = "";
            return evCount;
        } catch (Throwable t) {
            lastError = t.getClass().getSimpleName() + ": " + t.getMessage();
            return -1;
        }
    }

    public static int  getEventCount()        { return evCount; }
    public static long getTotalMicros()       { return totalMicros; }
    public static int  getInitialProgram(int c) {
        if (c < 0 || c >= 16) return 0;
        return initialProgramPerChannel[c];
    }
    public static long getEventTimeMicros(int i) { return (i < 0 || i >= evCount) ? 0L : evTimesMicros[i]; }
    public static int  getEventType(int i)       { return (i < 0 || i >= evCount) ? 0  : evType[i]; }
    public static int  getEventCh(int i)         { return (i < 0 || i >= evCount) ? 0  : evCh[i]; }
    public static int  getEventD1(int i)         { return (i < 0 || i >= evCount) ? 0  : evD1[i]; }
    public static int  getEventD2(int i)         { return (i < 0 || i >= evCount) ? 0  : evD2[i]; }

    public static void clearLoaded() {
        evTimesMicros = null;
        evType = evCh = evD1 = evD2 = null;
        evCount = 0;
        totalMicros = 0;
        Arrays.fill(initialProgramPerChannel, 0);
    }
}
