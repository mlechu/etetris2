;;; tetris2.el --- implementation of Tetris2 for Emacs  -*- lexical-binding:t -*-

;; Copyright (C) 1997, 2001-2022 Free Software Foundation, Inc.

;; Author: Glynn Clements <glynn@sensei.co.uk>
;; Old-Version: 2.01
;; Created: 1997-08-13
;; Keywords: games

;; This file is part of GNU Emacs.

;; GNU Emacs is free software: you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; GNU Emacs is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with GNU Emacs.  If not, see <https://www.gnu.org/licenses/>.

;;; Commentary:

;;; Code:

(eval-when-compile (require 'cl-lib))

(require 'gamegrid)

;; ;;;;;;;;;;;;; customization variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defgroup tetris2 nil
  "Play a game of Tetris2."
  :prefix "tetris2-"
  :group 'games)

(defcustom tetris2-use-glyphs t
  "Non-nil means use glyphs when available."
  :type 'boolean)

(defcustom tetris2-use-color t
  "Non-nil means use color when available."
  :type 'boolean)

(defcustom tetris2-draw-border-with-glyphs t
  "Non-nil means draw a border even when using glyphs."
  :type 'boolean)

(defcustom tetris2-default-tick-period 0.3
  "The default time taken for a shape to drop one row."
  :type 'number)

(defcustom tetris2-update-speed-function
  'tetris2-default-update-speed-function
  "Function run whenever the Tetris2 score changes.
Called with two arguments: (SHAPES ROWS)
SHAPES is the number of shapes which have been dropped.
ROWS is the number of rows which have been completed.

If the return value is a number, it is used as the timer period."
  :type 'function)

(defcustom tetris2-mode-hook nil
  "Hook run upon starting Tetris2."
  :type 'hook)

(defcustom tetris2-tty-colors
  ["yellow" "blue" "orange" "red" "green" "magenta" "cyan"]
  "Vector of colors of the various shapes in text mode."
  :type '(vector (color :tag "Shape 1")
                 (color :tag "Shape 2")
                 (color :tag "Shape 3")
                 (color :tag "Shape 4")
                 (color :tag "Shape 5")
                 (color :tag "Shape 6")
                 (color :tag "Shape 7")))

(defcustom tetris2-x-colors
  [[1 1 0]  [0 0 1] [0.9 0.4 0] [1 0 0] [0 1 0] [1 0 1] [0 1 1]]
  "Vector of RGB colors of the various shapes."
  :type '(vector (vector :tag "Shape 1" number number number)
                 (vector :tag "Shape 2" number number number)
                 (vector :tag "Shape 3" number number number)
                 (vector :tag "Shape 4" number number number)
                 (vector :tag "Shape 5" number number number)
                 (vector :tag "Shape 6" number number number)
                 (vector :tag "Shape 7" number number number)))

(defcustom tetris2-x-colors-ghost
  [[0.4 0.4 0] [0 0 0.4] [0.3 0.1 0] [0.4 0 0] [0 0.4 0] [0.4 0 0.4] [0 0.4 0.4]]
  "Vector of RGB colors of ghost shapes"
  :type '(vector (vector :tag "Shape 1" number number number)
                 (vector :tag "Shape 2" number number number)
                 (vector :tag "Shape 3" number number number)
                 (vector :tag "Shape 4" number number number)
                 (vector :tag "Shape 5" number number number)
                 (vector :tag "Shape 6" number number number)
                 (vector :tag "Shape 7" number number number)))

(defcustom tetris2-buffer-name "*Tetris2*"
  "Name used for Tetris2 buffer."
  :type 'string)

(defcustom tetris2-buffer-width 30
  "Width of used portion of buffer."
  :type 'number)

(defcustom tetris2-buffer-height 22
  "Height of used portion of buffer."
  :type 'number)

(defcustom tetris2-width 10
  "Width of playing area."
  :type 'number)

(defcustom tetris2-height 20
  "Height of playing area."
  :type 'number)

(defcustom tetris2-top-left-x 3
  "X position of top left of playing area."
  :type 'number)

(defcustom tetris2-top-left-y 1
  "Y position of top left of playing area."
  :type 'number)

(defvar tetris2-next-x (+ (* 2 tetris2-top-left-x) tetris2-width)
  "X position of next shape window.")

(defvar tetris2-next-y tetris2-top-left-y
  "Y position of next shape window.")

(defvar tetris2-score-x tetris2-next-x
  "X position of score.")

(defvar tetris2-score-y (+ tetris2-next-y 6)
  "Y position of score.")

(defvar tetris2-held-x tetris2-next-x
  "X position of held piece window.")

(defvar tetris2-held-y (+ tetris2-score-y 6)
  "Y position of held piece window.")

;; It is not safe to put this in /tmp.
;; Someone could make a symlink in /tmp
;; pointing to a file you don't want to clobber.
(defvar tetris2-score-file "tetris2-scores"
  ;; anybody with a well-connected server want to host this?
                                        ;(defvar tetris2-score-file "/anonymous@ftp.pgt.com:/pub/cgw/tetris2-scores"
  "File for holding high scores.")

;; ;;;;;;;;;;;;; display options ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar tetris2-blank-options
  '(((glyph colorize)
     (t ?\040))
    ((color-x color-x)
     (mono-x grid-x)
     (color-tty color-tty))
    (((glyph color-x) [0 0 0])
     (color-tty "black"))))

(defvar tetris2-cell-options
  '(((glyph colorize)
     (emacs-tty ?O)
     (t ?\040))
    ((color-x color-x)
     (mono-x mono-x)
     (color-tty color-tty)
     (mono-tty mono-tty))
    ;; color information is taken from tetris2-x-colors and tetris2-tty-colors
    ))

(defvar tetris2-border-options
  '(((glyph colorize)
     (t ?\+))
    ((color-x color-x)
     (mono-x grid-x)
     (color-tty color-tty))
    (((glyph color-x) [0.3 0.3 0.3])
     (color-tty "white"))))

(defvar tetris2-space-options
  '(((t ?\040))
    nil
    nil))

;; ;;;;;;;;;;;;; constants ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; y\x  0 1 2 3
;;  0  |_|_|_|_|
;;  1  |_|_|_|_|
;;  2  |_|_|_|_|
;;  3  |_|_|_|_|

(defconst tetris2-shapes
  [
   ;;O
   [[[0 0] [1 0] [0 1] [1 1]]]

   ;; J
   [[[0 0] [0 1] [1 1] [2 1]]
    [[1 0] [2 0] [1 1] [1 2]]
    [[0 1] [1 1] [2 1] [2 2]]
    [[1 0] [1 1] [0 2] [1 2]]]

   ;; L
   [[[2 0] [0 1] [1 1] [2 1]]
    [[1 0] [1 1] [1 2] [2 2]]
    [[0 1] [1 1] [2 1] [0 2]]
    [[0 0] [1 0] [1 1] [1 2]]]

   ;; Z
   [[[0 0] [1 0] [1 1] [2 1]]
    [[2 0] [1 1] [2 1] [1 2]]
    [[0 1] [1 1] [1 2] [2 2]]
    [[1 0] [0 1] [1 1] [0 2]]]

   ;; S
   [[[1 0] [2 0] [0 1] [1 1]]
    [[1 0] [1 1] [2 1] [2 2]]
    [[1 1] [2 1] [0 2] [1 2]]
    [[0 0] [0 1] [1 1] [1 2]]]

   ;; T
   [[[1 0] [0 1] [1 1] [2 1]]
    [[1 0] [1 1] [2 1] [1 2]]
    [[0 1] [1 1] [2 1] [1 2]]
    [[1 0] [0 1] [1 1] [1 2]]]

   ;; I
   [[[0 1] [1 1] [2 1] [3 1]]
    [[2 0] [2 1] [2 2] [2 3]]
    [[0 2] [1 2] [2 2] [3 2]]
    [[1 0] [1 1] [1 2] [1 3]]]]
  "Each shape is described by a vector that contains the coordinates of
each one of its four blocks.")

;;the scoring rules were taken from "xtetris2".  Blocks score differently
;;depending on their rotation

(defconst tetris2-shape-scores
  [[6] [6 7 6 7] [6 7 6 7] [6 7 6 7] [6 7 6 7] [5 5 6 5] [5 8 5 8]] )

(defconst tetris2-shape-dimensions
  [[2 2] [3 2] [3 2] [3 2] [3 2] [3 2] [4 1]])

(defconst tetris2-blank 14)

(defconst tetris2-border 15)

(defconst tetris2-space 16)

(defun tetris2-cell-open (x y)
  (let ((c (gamegrid-get-cell x y)))
    (or (= tetris2-blank c)
        (and (<= 7 c) (<= c 13)))))

(defun tetris2-default-update-speed-function (_shapes rows)
  (/ 20.0 (+ 50.0 rows)))

;; ;;;;;;;;;;;;; variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar-local tetris2-shape 0)
(defvar-local tetris2-rot 0)
(defvar-local tetris2-next-shape 0)
(defvar-local tetris2-n-shapes 0)
(defvar-local tetris2-n-rows 0)
(defvar-local tetris2-score 0)
(defvar-local tetris2-pos-x 0)
(defvar-local tetris2-pos-y 0)
(defvar-local tetris2-ghost-pos-y 0)
(defvar-local tetris2-held-shape tetris2-blank)
(defvar-local tetris2-can-hold t)
(defvar-local tetris2-paused nil)

;; ;;;;;;;;;;;;; keymaps ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defvar tetris2-mode-map
  (let ((map (make-sparse-keymap 'tetris2-mode-map)))
    (define-key map (kbd "n") 'tetris2-start-game)
    (define-key map (kbd "q") 'tetris2-end-game)
    (define-key map (kbd "p") 'tetris2-pause-game)
    (define-key map (kbd ".") 'tetris2-move-bottom)
    (define-key map (kbd "-") 'tetris2-move-left)
    (define-key map (kbd "=") 'tetris2-move-right)
    (define-key map (kbd " ") 'tetris2-move-down)
    (define-key map (kbd "a") 'tetris2-rotate-prev)
    (define-key map (kbd "d") 'tetris2-rotate-next)
    (define-key map (kbd "s") 'tetris2-rotate-180)
    (define-key map (kbd "w") 'tetris2-hold-shape)
    map)
  "Keymap for Tetris2 games.")

(defvar tetris2-null-map
  (let ((map (make-sparse-keymap 'tetris2-null-map)))
    (define-key map "n"		'tetris2-start-game)
    (define-key map "q"         'quit-window)
    map)
  "Keymap for finished Tetris2 games.")

(defconst tetris2--menu-def
  '("Tetris2"
    ["Start new game"    tetris2-start-game
     :help "Start a new Tetris2 game"]
    ["End game"          tetris2-end-game
     :active (tetris2-active-p)
     :help "End the current Tetris2 game"]
    ;; FIXME: Pause and resume from the menu currently doesn't work
    ;;        very well and is therefore disabled.  The game continues
    ;;        running while navigating the menu.  See also
    ;;        `snake--menu-def' which has the same problem.
    ;; ["Pause"             tetris2-pause-game
    ;;  :active (and (tetris2-active-p) (not tetris2-paused))
    ;;  :help "Pause running Tetris2 game"]
    ;; ["Resume"            tetris2-pause-game
    ;;  :active (and (tetris2-active-p) tetris2-paused)
    ;;  :help "Resume paused Tetris2 game"]
    )
  "Menu for `tetris2'.  Used to initialize menus.")

(easy-menu-define
  tetris2-mode-menu tetris2-mode-map
  "Menu for running Tetris2 games."
  tetris2--menu-def)

(easy-menu-define
  tetris2-null-menu tetris2-null-map
  "Menu for finished Tetris2 games."
  tetris2--menu-def)

;; ;;;;;;;;;;;;;;;; game functions ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(defun tetris2-display-options ()
  (let ((options (make-vector 256 nil)))
    (dotimes (c 256)
      (aset options c
            (cond ((= c tetris2-blank)
                   tetris2-blank-options)
                  ((and (>= c 0) (<= c 6))
                   (append
                    tetris2-cell-options
                    `((((glyph color-x) ,(aref tetris2-x-colors c))
                       (color-tty ,(aref tetris2-tty-colors c))
                       (t nil)))))
                  ((and (>= c 7) (<= c 13))
                   (append
                    tetris2-cell-options
                    `((((glyph color-x) ,(aref tetris2-x-colors-ghost (- c 7)))
                       (color-tty ,(aref tetris2-tty-colors (- c 7)))
                       (t nil)))))
                  ((= c tetris2-border)
                   tetris2-border-options)
                  ((= c tetris2-space)
                   tetris2-space-options)
                  (t
                   '(nil nil nil)))))
    options))

(defun tetris2-get-tick-period ()
  (let ((period (apply tetris2-update-speed-function
                       tetris2-n-shapes
                       tetris2-n-rows nil)))
    (and (numberp period) period)))

(defun tetris2-get-shape-cell (block)
  (aref (aref  (aref tetris2-shapes
                     tetris2-shape) tetris2-rot)
        block))

(defun tetris2-shape-width ()
  (aref (aref tetris2-shape-dimensions tetris2-shape) 0))

(defun tetris2-shape-rotations ()
  (length (aref tetris2-shapes tetris2-shape)))

(defun tetris2-draw-score ()
  (let ((strings (vector (format "Shapes: %05d" tetris2-n-shapes)
                         (format "Rows:   %05d" tetris2-n-rows)
                         (format "Score:  %05d" tetris2-score))))
    (dotimes (y 3)
      (let* ((string (aref strings y))
             (len (length string)))
        (dotimes (x len)
          (gamegrid-set-cell (+ tetris2-score-x x)
                             (+ tetris2-score-y y)
                             (aref string x)))))))

(defun tetris2-update-score ()
  (tetris2-draw-score)
  (let ((period (tetris2-get-tick-period)))
    (if period (gamegrid-set-timer period))))

(defun tetris2-new-shape ()
  (setq tetris2-shape tetris2-next-shape)
  (setq tetris2-rot 0)
  (setq tetris2-next-shape (random 7))
  (setq tetris2-pos-x (/ (- tetris2-width (tetris2-shape-width)) 2))
  (setq tetris2-pos-y 0)
  (if (tetris2-test-shape)
      (tetris2-end-game)
    (tetris2-draw-ghost)
    (tetris2-draw-shape)
    (tetris2-draw-next-shape)
    (tetris2-update-score)))

(defun tetris2-draw-next-shape ()
  (dotimes (x 4)
    (dotimes (y 4)
      (gamegrid-set-cell (+ tetris2-next-x x)
                         (+ tetris2-next-y y)
                         tetris2-blank)))
  (dotimes (i 4)
    (let ((tetris2-shape tetris2-next-shape)
          (tetris2-rot 0))
      (gamegrid-set-cell (+ tetris2-next-x
                            (aref (tetris2-get-shape-cell i) 0))
                         (+ tetris2-next-y
                            (aref (tetris2-get-shape-cell i) 1))
                         tetris2-shape))))

(defun tetris2-draw-held-shape ()
  (dotimes (x 4)
    (dotimes (y 4)
      (gamegrid-set-cell (+ tetris2-held-x x)
                         (+ tetris2-held-y y)
                         tetris2-blank)))
  (unless (= tetris2-held-shape tetris2-blank)
    (dotimes (i 4)
      (let ((tetris2-shape tetris2-held-shape)
            (tetris2-rot 0))
        (gamegrid-set-cell (+ tetris2-held-x
                              (aref (tetris2-get-shape-cell i) 0))
                           (+ tetris2-held-y
                              (aref (tetris2-get-shape-cell i) 1))
                           tetris2-shape)))))

(defun tetris2-draw-ghost ()
  (let ((hit nil)
        (bottom-y tetris2-pos-y))
    (while (not hit)
      (setq bottom-y (1+ bottom-y))
      (dotimes (i 4)
        (unless hit
          (setq hit
                (let* ((c (tetris2-get-shape-cell i))
                       (xx (+ tetris2-pos-x
                              (aref c 0)))
                       (yy (+ bottom-y
                              (aref c 1))))
                  (or (>= xx tetris2-width)
                      (>= yy tetris2-height)
                      (not (tetris2-cell-open
                            (+ xx tetris2-top-left-x)
                            (+ yy tetris2-top-left-y)))))))))
    (setq tetris2-ghost-pos-y (1- bottom-y))
    (dotimes (i 4)
      (let ((c (tetris2-get-shape-cell i)))
        (gamegrid-set-cell (+ tetris2-top-left-x
                              tetris2-pos-x
                              (aref c 0))
                           (+ tetris2-top-left-y
                              tetris2-ghost-pos-y
                              (aref c 1))
                           (+ 7 tetris2-shape))))))

(defun tetris2-draw-shape ()
  (dotimes (i 4)
    (let ((c (tetris2-get-shape-cell i)))
      (gamegrid-set-cell (+ tetris2-top-left-x
                            tetris2-pos-x
                            (aref c 0))
                         (+ tetris2-top-left-y
                            tetris2-pos-y
                            (aref c 1))
                         tetris2-shape))))

(defun tetris2-erase-shape ()
  (dotimes (i 4)
    (let ((c (tetris2-get-shape-cell i)))
      (gamegrid-set-cell (+ tetris2-top-left-x
                            tetris2-pos-x
                            (aref c 0))
                         (+ tetris2-top-left-y
                            tetris2-pos-y
                            (aref c 1))
                         tetris2-blank))))

(defun tetris2-erase-ghost ()
  (dotimes (i 4)
    (let ((c (tetris2-get-shape-cell i)))
      (gamegrid-set-cell (+ tetris2-top-left-x
                            tetris2-pos-x
                            (aref c 0))
                         (+ tetris2-top-left-y
                            tetris2-ghost-pos-y
                            (aref c 1))
                         tetris2-blank))))

(defun tetris2-test-shape ()
  (let ((hit nil))
    (dotimes (i 4)
      (unless hit
        (setq hit
              (let* ((c (tetris2-get-shape-cell i))
                     (xx (+ tetris2-pos-x
                            (aref c 0)))
                     (yy (+ tetris2-pos-y
                            (aref c 1))))
                (or (>= xx tetris2-width)
                    (>= yy tetris2-height)
                    (not (tetris2-cell-open
                          (+ xx tetris2-top-left-x)
                          (+ yy tetris2-top-left-y))))))))
    hit))

(defun tetris2-full-row (y)
  (let ((full t))
    (dotimes (x tetris2-width)
      (if (= (gamegrid-get-cell (+ tetris2-top-left-x x)
                                (+ tetris2-top-left-y y))
             tetris2-blank)
          (setq full nil)))
    full))

(defun tetris2-shift-row (y)
  (if (= y 0)
      (dotimes (x tetris2-width)
        (gamegrid-set-cell (+ tetris2-top-left-x x)
                           (+ tetris2-top-left-y y)
                           tetris2-blank))
    (dotimes (x tetris2-width)
      (let ((c (gamegrid-get-cell (+ tetris2-top-left-x x)
                                  (+ tetris2-top-left-y y -1))))
        (gamegrid-set-cell (+ tetris2-top-left-x x)
                           (+ tetris2-top-left-y y)
                           c)))))

(defun tetris2-shift-down ()
  (dotimes (y0 tetris2-height)
    (when (tetris2-full-row y0)
      (setq tetris2-n-rows (1+ tetris2-n-rows))
      (cl-loop for y from y0 downto 0 do
               (tetris2-shift-row y)))))

(defun tetris2-draw-border-p ()
  (or (not (eq gamegrid-display-mode 'glyph))
      tetris2-draw-border-with-glyphs))

(defun tetris2-init-buffer ()
  (gamegrid-init-buffer tetris2-buffer-width
                        tetris2-buffer-height
                        tetris2-space)
  (let ((buffer-read-only nil))
    (if (tetris2-draw-border-p)
        (cl-loop for y from -1 to tetris2-height do
                 (cl-loop for x from -1 to tetris2-width do
                          (gamegrid-set-cell (+ tetris2-top-left-x x)
                                             (+ tetris2-top-left-y y)
                                             tetris2-border))))
    (dotimes (y tetris2-height)
      (dotimes (x tetris2-width)
        (gamegrid-set-cell (+ tetris2-top-left-x x)
                           (+ tetris2-top-left-y y)
                           tetris2-blank)))
    (if (tetris2-draw-border-p)
        (cl-loop for y from -1 to 4 do
                 (cl-loop for x from -1 to 4 do
                          (gamegrid-set-cell (+ tetris2-next-x x)
                                             (+ tetris2-next-y y)
                                             tetris2-border)
                          (gamegrid-set-cell (+ tetris2-held-x x)
                                             (+ tetris2-held-y y)
                                             tetris2-border))))))

(defun tetris2-reset-game ()
  (gamegrid-kill-timer)
  (tetris2-init-buffer)
  (setq tetris2-next-shape (random 7))
  (setq tetris2-shape	0
        tetris2-rot	0
        tetris2-pos-x	0
        tetris2-pos-y	0
        tetris2-n-shapes	0
        tetris2-n-rows	0
        tetris2-score	0
        tetris2-can-hold t
        tetris2-held-shape tetris2-blank
        tetris2-paused	nil)
  (tetris2-new-shape))

(defun tetris2-shape-done ()
  (tetris2-shift-down)
  (setq tetris2-n-shapes (1+ tetris2-n-shapes))
  (setq tetris2-score
        (+ tetris2-score
           (aref (aref tetris2-shape-scores tetris2-shape) tetris2-rot)))
  (setq tetris2-can-hold t)
  (tetris2-update-score)
  (tetris2-new-shape))

(defun tetris2-update-game (tetris2-buffer)
  "Called on each clock tick.
Drops the shape one square, testing for collision."
  (if (and (not tetris2-paused)
           (eq (current-buffer) tetris2-buffer))
      (let (hit)
        (tetris2-erase-shape)
        (tetris2-erase-ghost)
        (setq tetris2-pos-y (1+ tetris2-pos-y))
        (setq hit (tetris2-test-shape))
        (if hit
            (setq tetris2-pos-y (1- tetris2-pos-y)))
        (tetris2-draw-ghost)
        (tetris2-draw-shape)
        (if hit
            (tetris2-shape-done)))))

(defun tetris2-move-bottom ()
  "Drop the shape to the bottom of the playing area."
  (interactive nil tetris2-mode)
  (unless tetris2-paused
    (let ((hit nil))
      (tetris2-erase-shape)
      (tetris2-erase-ghost)
      (while (not hit)
        (setq tetris2-pos-y (1+ tetris2-pos-y))
        (setq hit (tetris2-test-shape)))
      (setq tetris2-pos-y (1- tetris2-pos-y))
      (tetris2-draw-shape)
      (tetris2-shape-done))))

(defun tetris2-move-left ()
  "Move the shape one square to the left."
  (interactive nil tetris2-mode)
  (unless tetris2-paused
    (tetris2-erase-shape)
    (tetris2-erase-ghost)
    (setq tetris2-pos-x (1- tetris2-pos-x))
    (if (tetris2-test-shape)
        (setq tetris2-pos-x (1+ tetris2-pos-x)))
    (tetris2-draw-ghost)
    (tetris2-draw-shape)))

(defun tetris2-move-right ()
  "Move the shape one square to the right."
  (interactive nil tetris2-mode)
  (unless tetris2-paused
    (tetris2-erase-shape)
    (tetris2-erase-ghost)
    (setq tetris2-pos-x (1+ tetris2-pos-x))
    (if (tetris2-test-shape)
        (setq tetris2-pos-x (1- tetris2-pos-x)))
    (tetris2-draw-ghost)
    (tetris2-draw-shape)))

(defun tetris2-move-down ()
  "Move the shape one square to the bottom."
  (interactive nil tetris2-mode)
  (unless tetris2-paused
    (tetris2-erase-shape)
    (tetris2-erase-ghost)
    (setq tetris2-pos-y (1+ tetris2-pos-y))
    (if (tetris2-test-shape)
        (setq tetris2-pos-y (1- tetris2-pos-y)))
    (tetris2-draw-ghost)
    (tetris2-draw-shape)))

(defun tetris2-rotate-prev ()
  "Rotate the shape anticlockwise."
  (interactive nil tetris2-mode)
  (unless tetris2-paused
    (tetris2-erase-shape)
    (tetris2-erase-ghost)
    (setq tetris2-rot (% (+ 3 tetris2-rot)
                         (tetris2-shape-rotations)))
    (if (tetris2-test-shape)
        (setq tetris2-rot (% (+ 1 tetris2-rot)
                             (tetris2-shape-rotations))))
    (tetris2-draw-ghost)
    (tetris2-draw-shape)))

(defun tetris2-rotate-next ()
  "Rotate the shape clockwise."
  (interactive nil tetris2-mode)
  (unless tetris2-paused
    (tetris2-erase-shape)
    (tetris2-erase-ghost)
    (setq tetris2-rot (% (+ 1 tetris2-rot)
                         (tetris2-shape-rotations)))
    (if (tetris2-test-shape)
        (setq tetris2-rot (% (+ 3 tetris2-rot)
                             (tetris2-shape-rotations))))
    (tetris2-draw-ghost)
    (tetris2-draw-shape)))

(defun tetris2-rotate-180 ()
  "Rotate the shape 180 degrees."
  (interactive nil tetris2-mode)
  (unless tetris2-paused
    (tetris2-erase-shape)
    (tetris2-erase-ghost)
    (setq tetris2-rot (% (+ 2 tetris2-rot)
                         (tetris2-shape-rotations)))
    (if (tetris2-test-shape)
        (setq tetris2-rot (% (+ 2 tetris2-rot)
                             (tetris2-shape-rotations))))
    (tetris2-draw-ghost)
    (tetris2-draw-shape)))

(defun tetris2-hold-shape ()
  "Save the shape for later."
  (interactive nil tetris2-mode)
  (unless (or tetris2-paused (not tetris2-can-hold))
    (tetris2-erase-shape)
    (tetris2-erase-ghost)
    (let ((old-held tetris2-held-shape))
      (setq tetris2-held-shape tetris2-shape)
      (if (= old-held tetris2-blank)
          (setq tetris2-shape tetris2-next-shape
                tetris2-next-shape (random 7))
        (setq tetris2-shape old-held)))
    (setq tetris2-pos-x (/ (- tetris2-width (tetris2-shape-width)) 2)
          tetris2-pos-y 0
          tetris2-rot 0
          tetris2-can-hold nil)
    (if (tetris2-test-shape)
        (tetris2-end-game)
      (tetris2-draw-ghost)
      (tetris2-draw-shape)
      (tetris2-draw-next-shape)
      (tetris2-draw-held-shape))))

(defun tetris2-end-game ()
  "Terminate the current game."
  (interactive nil tetris2-mode)
  (gamegrid-kill-timer)
  (use-local-map tetris2-null-map)
  (gamegrid-add-score tetris2-score-file tetris2-score))

(defun tetris2-start-game ()
  "Start a new game of Tetris2."
  (interactive nil tetris2-mode)
  (tetris2-reset-game)
  (use-local-map tetris2-mode-map)
  (let ((period (or (tetris2-get-tick-period)
                    tetris2-default-tick-period)))
    (gamegrid-start-timer period 'tetris2-update-game)))

(defun tetris2-pause-game ()
  "Pause (or resume) the current game."
  (interactive nil tetris2-mode)
  (setq tetris2-paused (not tetris2-paused))
  (message (and tetris2-paused "Game paused (press p to resume)")))

(defun tetris2-active-p ()
  (eq (current-local-map) tetris2-mode-map))

(put 'tetris2-mode 'mode-class 'special)

(define-derived-mode tetris2-mode nil "Tetris2"
  "A mode for playing Tetris2."
  :interactive nil

  (add-hook 'kill-buffer-hook 'gamegrid-kill-timer nil t)

  (use-local-map tetris2-null-map)

  (setq show-trailing-whitespace nil)

  (setq gamegrid-use-glyphs tetris2-use-glyphs)
  (setq gamegrid-use-color tetris2-use-color)

  (gamegrid-init (tetris2-display-options)))

;;;###autoload
(defun tetris2 ()
  "Play the Tetris2 game.
Shapes drop from the top of the screen, and the user has to move and
rotate the shape to fit in with those at the bottom of the screen so
as to form complete rows.

`tetris2-mode' keybindings:
\\<tetris2-mode-map>
\\[tetris2-start-game]	Start a new game of Tetris2
\\[tetris2-end-game]	Terminate the current game
\\[tetris2-pause-game]	Pause (or resume) the current game
\\[tetris2-move-left]	Move the shape one square to the left
\\[tetris2-move-right]	Move the shape one square to the right
\\[tetris2-rotate-prev]	Rotate the shape clockwise
\\[tetris2-rotate-next]	Rotate the shape anticlockwise
\\[tetris2-rotate-180]	Rotate the shape 180 degrees
\\[tetris2-move-bottom]	Drop the shape to the bottom of the playing area
\\[tetris2-hold-shape]	Hold the current shape for later"
  (interactive)

  (select-window (or (get-buffer-window tetris2-buffer-name)
                     (selected-window)))
  (switch-to-buffer tetris2-buffer-name)
  (gamegrid-kill-timer)
  (tetris2-mode)
  (tetris2-start-game))

(provide 'tetris2)

;;; tetris2.el ends here
