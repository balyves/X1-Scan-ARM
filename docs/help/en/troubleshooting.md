# Troubleshooting

Every error message of X1 Scan has a “Help” button. It opens the entry of the same name here. These entries add to the message: when the case happens, and what it means.

A safety check may stop the scanner. This is on purpose: it protects the device as soon as a response differs from what is known. The message says what to do.

The “Details” part of a message holds the technical text. “Copy Details” copies it for a bug report. For the real X1, the log in the X1-captures folder of your home folder keeps all the details too.

## Access to the X1 {#access}

### No X1 found {#no-scanner}

- The Mac sees the X1 only when it is on, connected and recognised by the FireWire driver.
- On macOS 26 Tahoe, this driver is ASFireWire. Without it, the X1 stays invisible, even when on.
- USB to FireWire adapters do not work. See [Connect the X1](first-scan.md#connect).
- Without a scanner, you can try the application in [discovery mode](discovery.md).

### The X1 is busy {#scanner-busy}

- Only one program at a time can open the scanner.
- FlexColor keeps the scanner as long as it is open. Quit it completely.

### This scanner is not an X1 {#not-an-x1}

- X1 Scan reads the scanner’s identity first. If it is not a Flextight X1, it stops there.
- Other Flextight models are not supported.

### The X1 could not be read {#scanner-read-failed}

- Reading only sends requests for information. Nothing moves.
- Restarting the X1 is often enough.
- If it happens again, the “Details” part gives the code to add to a report.

### The X1 no longer answers {#disconnected}

- A cable that moves, an adapter not pushed in, or a power cut can break the exchange.
- After a cut during a preview or a scan, the X1 must be switched off and on again.

### The X1 did not answer in time {#scanner-timeout}

- Every command has a time limit. A command without an answer stops the operation.
- The usual causes are the adapter chain or the cable.

## Starting a preview or a scan {#start}

### Reference sequences missing {#capture-missing}

- X1 Scan drives the real X1 only with validated sequences, shipped in the application.
- If they are missing, the application is incomplete. Nothing is sent to the scanner.

### The log could not be created {#log-failed}

- Every session on the real X1 is written to a log, in the X1-captures folder.
- It is a safety measure: without a log, X1 Scan sends nothing.

## Safety checks {#safety}

A safety check compares every command and every response with a validated sequence. At the first difference, it stops everything. The scanner is not necessarily broken: the stop is on purpose, to protect it.

After a stop by a safety check, switch the X1 off and on again before starting again, unless the message says otherwise.

### Command refused {#guard-refused}

- The blocked command was never sent.
- This points to a problem in X1 Scan. A bug report with the details helps to fix it.

### Unexpected state {#unexpected-state}

- During a sequence, the scanner reports its state regularly. An unexpected state stops the sequence.
- A holder not fully in can cause it.

### Waited too long {#state-timeout}

- The scanner had to reach a state within a time limit. It did not.
- Check that nothing hinders the holder’s movement.

### Unexpected position {#position-out-of-tolerance}

- X1 Scan checks the carriage’s position at several moments.
- A difference that is too large stops the sequence before the next movement.

### Position out of range {#position-out-of-range}

- Before focusing, the position read must stay within a validated range.
- Switch the X1 off and on, then run a complete preview before scanning.

### Carriage position {#carriage-position}

- Before placing the carriage for the preview, X1 Scan checks its position.
- If it is not the expected one, the preview stops before the carriage is positioned.

### Unknown starting state {#start-state-unknown}

- X1 Scan knows two starting states: right after power-on, and after earlier use.
- Here, neither matched. Only reads, the startup command and the session start were sent: no window, mode or image.

### Preview needed {#scan-needs-preview}

- A scan always follows a complete preview, with no restart in between.
- After restarting the X1, run a preview first.

### Line counter {#line-counter}

- The scanner’s line counter must always move forward.
- Going back stops the sequence.

### Unexpected response {#unexpected-response}

- The scanner returned a status, a length or a content other than the validated sequence’s.
- The “Details” part gives the step and the value received.

## Stop {#stop}

### Stopped on request {#stopped-by-user}

- Stop (⌘. or Esc), a change of source or quitting the application stop the running sequence.
- Once scanning has started (first SCAN), X1 Scan sends the stop command and waits for the scanner to be ready.
- On the real X1, the message says whether the X1 must be switched off and on.

### The stop sequence did not complete {#stop-incomplete}

- The scanner did not confirm it was ready after the stop command.
- Start nothing else before switching it off and on again.

## Image and files {#files}

### The image could not be decoded {#decoding-failed}

- The scanner finished its sequence. Only turning the lines into an image failed.
- The X1 does not need a restart.

### No export folder {#no-export-folder}

- See [Folder](output.md#folder).

### Export folder not found {#export-folder-missing}

- An external disk disconnected or a renamed folder give this message.

### The file could not be written {#write-failed}

- An existing file is never overwritten: that is not the cause.
- After a scan, the image stays shown. You can export it elsewhere with File › Export….

### No holder, or holder not supported {#holder-missing}

- This message is planned for a later version. X1 Scan does not detect the holder yet.

### Unexpected error {#unknown}

- A case X1 Scan does not know yet.
- The “Details” part holds everything useful for a bug report.
