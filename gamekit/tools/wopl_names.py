"""Names a WOPL instrument bank's instruments, for SONGKIT's bank page: those without a name
get their General MIDI one (in a melodic bank, the program's; in a percussion bank, the
drum on that key), cut to SONGKIT's 16 characters; and banks without a name, the ones given.
Instruments that already have names are left as they are. The file is changed in place.

    python wopl_names.py BANK.WOP ["melodic bank's name" ["percussion bank's name"]]

(Many banks -- The Fat Man's among them -- come with no names at all; SONGKIT's bank
page would show only numbers.) WOPL: github.com/Wohlstand/OPL3BankEditor, its
WOPL-and-OPLI-Specification.txt; gamekit/README.md has the parts SONGKIT reads.
"""
import struct
import sys

GM = ["Grand Piano", "Bright Piano", "Electric Grand", "Honky-tonk Piano", "Electric Piano 1",
      "Electric Piano 2", "Harpsichord", "Clavinet", "Celesta", "Glockenspiel", "Music Box",
      "Vibraphone", "Marimba", "Xylophone", "Tubular Bells", "Dulcimer", "Drawbar Organ",
      "Percussive Organ", "Rock Organ", "Church Organ", "Reed Organ", "Accordion", "Harmonica",
      "Tango Accordion", "Nylon Guitar", "Steel Guitar", "Jazz Guitar", "Clean Guitar",
      "Muted Guitar", "Overdrive Guitar", "Distortion Gtr", "Guitar Harmonics", "Acoustic Bass",
      "Fingered Bass", "Picked Bass", "Fretless Bass", "Slap Bass 1", "Slap Bass 2",
      "Synth Bass 1", "Synth Bass 2", "Violin", "Viola", "Cello", "Contrabass",
      "Tremolo Strings", "Pizzicato", "Orchestral Harp", "Timpani", "Strings 1", "Strings 2",
      "Synth Strings 1", "Synth Strings 2", "Choir Aahs", "Voice Oohs", "Synth Voice",
      "Orchestra Hit", "Trumpet", "Trombone", "Tuba", "Muted Trumpet", "French Horn",
      "Brass Section", "Synth Brass 1", "Synth Brass 2", "Soprano Sax", "Alto Sax", "Tenor Sax",
      "Baritone Sax", "Oboe", "English Horn", "Bassoon", "Clarinet", "Piccolo", "Flute",
      "Recorder", "Pan Flute", "Blown Bottle", "Shakuhachi", "Whistle", "Ocarina",
      "Square Lead", "Saw Lead", "Calliope Lead", "Chiff Lead", "Charang Lead", "Voice Lead",
      "Fifths Lead", "Bass + Lead", "New Age Pad", "Warm Pad", "Polysynth Pad", "Choir Pad",
      "Bowed Pad", "Metallic Pad", "Halo Pad", "Sweep Pad", "Rain", "Soundtrack", "Crystal",
      "Atmosphere", "Brightness", "Goblins", "Echoes", "Sci-fi", "Sitar", "Banjo", "Shamisen",
      "Koto", "Kalimba", "Bagpipe", "Fiddle", "Shanai", "Tinkle Bell", "Agogo", "Steel Drums",
      "Woodblock", "Taiko Drum", "Melodic Tom", "Synth Drum", "Reverse Cymbal",
      "Gtr Fret Noise", "Breath Noise", "Seashore", "Bird Tweet", "Telephone Ring",
      "Helicopter", "Applause", "Gunshot"]
DRUMS = {35: "Acou Bass Drum", 36: "Bass Drum 1", 37: "Side Stick", 38: "Acoustic Snare",
         39: "Hand Clap", 40: "Electric Snare", 41: "Low Floor Tom", 42: "Closed Hi-hat",
         43: "High Floor Tom", 44: "Pedal Hi-hat", 45: "Low Tom", 46: "Open Hi-hat",
         47: "Low-Mid Tom", 48: "Hi-Mid Tom", 49: "Crash Cymbal 1", 50: "High Tom",
         51: "Ride Cymbal 1", 52: "Chinese Cymbal", 53: "Ride Bell", 54: "Tambourine",
         55: "Splash Cymbal", 56: "Cowbell", 57: "Crash Cymbal 2", 58: "Vibraslap",
         59: "Ride Cymbal 2", 60: "Hi Bongo", 61: "Low Bongo", 62: "Mute Hi Conga",
         63: "Open Hi Conga", 64: "Low Conga", 65: "High Timbale", 66: "Low Timbale",
         67: "High Agogo", 68: "Low Agogo", 69: "Cabasa", 70: "Maracas", 71: "Short Whistle",
         72: "Long Whistle", 73: "Short Guiro", 74: "Long Guiro", 75: "Claves",
         76: "Hi Wood Block", 77: "Low Wood Block", 78: "Mute Cuica", 79: "Open Cuica",
         80: "Mute Triangle", 81: "Open Triangle"}
assert len(GM) == 128 and all(len(n) <= 16 for n in GM + list(DRUMS.values()))


def main():
    path = sys.argv[1]
    names = sys.argv[2:4]
    d = bytearray(open(path, "rb").read())
    if d[:11] != b"WOPL3-BANK\0":
        sys.exit("%s: not a WOPL bank" % path)
    ver = struct.unpack("<H", d[11:13])[0]
    mb, pb = struct.unpack(">HH", d[13:17])
    size = 66 if ver >= 3 else 62
    meta = 19
    base = meta + (34 * (mb + pb) if ver >= 2 else 0)
    named = 0
    for k in range(mb + pb):
        perc = k >= mb
        if ver >= 2:
            at = meta + 34 * k
            want = names[1 if perc else 0] if len(names) > (1 if perc else 0) else None
            if want and not d[at]:
                d[at:at + 32] = want.encode("ascii")[:31].ljust(32, b"\0")
        for p in range(128):
            at = base + (k * 128 + p) * size
            if d[at] or d[at + 39] & 4:
                continue  # (named already, or blank)
            name = DRUMS.get(p) if perc else GM[p]
            if name:
                d[at:at + 32] = name.encode("ascii").ljust(32, b"\0")
                named += 1
    open(path, "wb").write(d)
    print("%s: %d instruments named" % (path, named))


if __name__ == "__main__":
    main()
