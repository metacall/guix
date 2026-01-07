(use-modules (guix channels) (srfi srfi-1))

; Load the list from the file path
(define channels-file (load "/root/.config/guix/channels.scm"))

; Extract the commit from guix channel
(let ((chan (find (lambda (c) (eq? (channel-name c) 'guix)) channels-file)))
  (if chan
      (display (channel-commit chan))
      (display "Channel not found")))
