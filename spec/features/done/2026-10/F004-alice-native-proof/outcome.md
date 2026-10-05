# Outcome

PASS. Alice's native chat-panels scenario (`scripts/debug/native-chat-panels.sh`, live OpenAI, both Quiet-tools modes, 20 takes, 0 layout defects, exit 0, 211 s) ran with its lab window on virtual display 56 the whole time; the window was never on screen anywhere else. The frontmost app was Slack in all 701 samples (before, during every 0.2 s, after); the lab process was never frontmost. Shot (a) shows the Alice window mid-answer on the virtual display; shot (b), taken at the same moment, shows Adam's main display with no Alice window. Evidence: `evidence/` here (summary, window track, take list, downscaled shot a); full run including both main-display shots at `proof/20261005T130111/` (gitignored: it holds Adam's screen).

The first passing run (`proof/20261005T125549/`) showed a ~6 s system dialog: macOS 26 ScreenCaptureKit asks for microphone access on behalf of `vscreen shot`, and the request was still undetermined. Fixed in f74e68f by signing with the hardened runtime: tccd now denies the microphone check for lack of the audio-input entitlement and shows nothing (observed in the tccd log). Run 3 above is the clean run after that fix.

The lab window is placed by a 17-line Alice hook used only in a throwaway worktree; it is written up for Adam in `alice-hook.md`. tao's launch-time activation did not take the front in either run.
