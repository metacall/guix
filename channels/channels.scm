(use-modules (guix ci))

(list (channel-with-substitutes-available
        (channel
          (name 'guix)
          (url "https://git.guix.gnu.org/guix.git")
          (branch "master")
          (introduction
            (make-channel-introduction
              "9edb3f66fd807b096b48283debdcddccfea34bad"
              (openpgp-fingerprint
                "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA"))))
        "https://ci.guix.gnu.org"))

; (list
;   (channel
;     (name 'guix)
;     (url "https://codeberg.org/guix/guix.git")
;     (branch "master")
;     (introduction
;       (make-channel-introduction
;         "9edb3f66fd807b096b48283debdcddccfea34bad"
;         (openpgp-fingerprint
;           "BBB0 2DDF 2CEA F6A8 0D1D  E643 A2A0 6DF2 A33A 54FA")))))
