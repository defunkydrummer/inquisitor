#|
  This code is a part of inquisitor project
  and a derivate from guess (https://github.com/zqwell/guess).
|#
;;; This code is derivative of libguess-1.0 and guess-0.1.0 for common lisp.
;;; 
;;; Copyright (c) 2011 zqwell <zqwell@gmail.com>
;;; 
;;; The following is the original copyright notice.
;;; 
;;; Redistribution and use in source and binary forms, with or without
;;; modification, are permitted provided that the following conditions
;;; are met:
;;; 
;;; 1. Redistributions of source code must retain the above copyright
;;;    notice, this list of conditions and the following disclaimer.
;;; 
;;; 2. Redistributions in binary form must reproduce the above copyright
;;;    notice, this list of conditions and the following disclaimer in the
;;;    documentation and/or other materials provided with the distribution.
;;; 
;;; 3. Neither the name of the authors nor the names of its contributors
;;;    may be used to endorse or promote products derived from this
;;;    software without specific prior written permission.
;;; 
;;; THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
;;; "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
;;; LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
;;; A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
;;; OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
;;; SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED
;;; TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
;;; PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
;;; LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING
;;; NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
;;; SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
;;; 
;;; Copyright (c) 2000-2003 Shiro Kawai, All rights reserved.
;;; 

(in-package :cl-user)
(defpackage inquisitor.encoding.guess
  (:use :cl
        :inquisitor.encoding.table)
  (:import-from :inquisitor.encoding.dfa
                :dfa-process
                :dfa-none
                :dfa-top
                :dfa-name
                :generate-order)
  (:import-from :alexandria
                :once-only
                :with-unique-names)
  (:import-from :anaphora
                :aif
                :awhen
                :it)
  (:export :list-available-scheme
           :ces-guess-from-vector))
(in-package :inquisitor.encoding.guess)

(defparameter +schemes+
  '((:jp guess-jp)   ;; japanese
    (:tw guess-tw)   ;; taiwanese
    (:cn guess-cn)   ;; chinese
    (:kr guess-kr)   ;; korean
    (:ru guess-ru)   ;; russian
    (:ar guess-ar)   ;; arabic
    (:tr guess-tr)   ;; turkish
    (:gr guess-gr)   ;; greek
    (:hw guess-hw)   ;; hebrew
    (:pl guess-pl)   ;; polish
    (:es guess-es)   ;; spanish
    (:bl guess-bl))) ;; baltic

(defun list-available-scheme ()
  (mapcar #'car +schemes+))

(defun ces-guess-from-vector (vector scheme &optional order state)
  "Guess character encoding scheme under the language `scheme`. `order` is a _dfa state_:
_dfa state_ is a list consist of a) nodes of dfa, b) arrows of dfa c) score and d) name.
`state` is a state except dfa state. `state` may be used or not be used by each guess-*
function of scheme, although you must be pass to this function.
Specifying `order` and `state` means, we can restart guessing from the point of `order`
and `state`.

`ces-guess-from-vector` returns `encoding` and `order`: `encoding` is an _implementation
independent_ name, `order` is a state at this function stops guessing process."

  (macrolet ((guess (fn-name) `(funcall ,fn-name vector order state)))
    (let ((fn-name (cadr (find scheme +schemes+ :key #'car))))
      (if fn-name
          (guess fn-name)
          (error (format nil "scheme parameter (~A): not supported." scheme))))))

(defmacro do-guess-loop ((&rest lookahead-vars) buffer &body body)
  (once-only (buffer)
    (with-unique-names (idx len)
      (let ((last-var (car (last lookahead-vars))))
        `(let* ((,len (length ,buffer))
                (,idx ,(length lookahead-vars))
                ,@(loop
                     for i from 0
                     for var in lookahead-vars
                     collect `(,var (if (< (the fixnum ,i) (the fixnum ,len))
                                        (aref ,buffer (the fixnum ,i))
                                        (the fixnum 0)))))
          (loop named stride-over-buffer
             do (progn
                  ,@body
                  ,@(loop
                       for var1 in lookahead-vars
                       for var2 in (cdr lookahead-vars)
                       collect `(setf ,var1 ,var2))
                  (unless (< (the fixnum ,idx) (the fixnum ,len))
                    (return-from stride-over-buffer))
                  (setf ,last-var (aref ,buffer (the fixnum ,idx)))
                  (incf (the fixnum ,idx)))))))))

(defmacro check-byte-order-mark (buffer big-endian-value little-endian-value order state)
  (once-only (buffer order)
    `(when (>= (the fixnum (length ,buffer)) (the fixnum 2))
       (cond ((and (= (aref ,buffer (the fixnum 0)) (the fixnum #xfe))
                   (= (aref ,buffer (the fixnum 1)) (the fixnum #xff)))
              (return-from guess-body (values ,big-endian-value ,order ,state)))
             ((and (= (aref ,buffer (the fixnum 0)) (the fixnum #xff))
                   (= (aref ,buffer (the fixnum 1)) (the fixnum #xfe)))
              (return-from guess-body (values ,little-endian-value ,order ,state)))
             (t nil)))))

(defmacro guess ((buffer order state (&rest vars) (&rest encs)) &body specialized-check)
  (once-only (buffer order)
    (with-unique-names (order-var)
      `(block guess-body
         (let ((,order-var (if ,order
                               ,order
                               (generate-order ,@encs))))
           ;; special treatment of BOM
           (unless ,order-var
             (check-byte-order-mark ,buffer :ucs-2be :ucs-2le ,order-var ,state))

           (do-guess-loop ,vars ,buffer
             ,@specialized-check
             (awhen (dfa-process ,order-var ,(first vars))
               (return-from guess-body (values it ,order-var ,state)))
             (when (dfa-none ,order-var)
               (return-from guess-body (values nil ,order-var ,state))))

           (aif (dfa-top ,order-var)
                (values (dfa-name it) ,order-var ,state)
                (values nil ,order-var ,state)))))))


(defun guess-jp (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :cp932 :euc-jp))
    ;; special treatment of iso-2022 escape sequence
    (cond ((= (the fixnum c1) (the fixnum #x1b))
           (setf state :iso-2022-jp-escape-1))
          ((eq state :iso-2022-jp-escape-1)
           (if (or (= (the fixnum c1) (the fixnum #x24))   ; $
                   (= (the fixnum c1) (the fixnum #x28))) ; ()
               (return-from guess-body (values :iso-2022-jp order nil))
               (setf state nil))))))

(defun guess-tw (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :big5))
    ;; special treatment of iso-2022 escape sequence
    (when (= (the fixnum c1) (the fixnum #x1b))
      (setf state :iso-2022-tw-escape-1))
    (if (and (eq state :iso-2022-tw-escape-1)
             (or (= (the fixnum c1) (the fixnum #x24))   ; $
                 (= (the fixnum c1) (the fixnum #x28)))) ; (
        (return-from guess-body (values :iso-2022-tw order nil))
        (setf state nil))))

(defun guess-cn (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :gb2312 :gb18030))
    ;; special treatment of iso-2022 escape sequence
    (when (= (the fixnum c1) (the fixnum #x1b))
      (setf state :iso-2022-cn-escape-1))
    (when (eq state :iso-2022-cn-escape-1)
      (if (= (the fixnum c1) (the fixnum #x24))           ; $
          (setf state :iso-2022-cn-escape-2)
          (setf state nil)))
    (if (and (eq state :iso-2022-cn-escape-2)
             (or (= (the fixnum c1) (the fixnum #x29))       ; )
                 (= (the fixnum c1) (the fixnum #x2B))))     ; +
        (return-from guess-body (values :iso-2022-cn order nil))
        (setf state nil))))

(defun guess-kr (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :euc-kr :johab))
    ;; special treatment of iso-2022 escape sequence
    (when (= (the fixnum c1) (the fixnum #x1b))
      (setf state :iso-2022-kr-escape-1))
    (when (eq state :iso-2022-kr-escape-1)
      (if (= (the fixnum c1) (the fixnum #x24))
          (setf state :iso-2022-kr-escape-2)      ; $
          (setf state nil)))
    (when (eq state :iso-2022-kr-escape-2)
      (if (= (the fixnum c3) (the fixnum #x29))     ; )
          (return-from guess-body :iso-2022-kr)
          (setf state nil)))))

(defun guess-ar (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :iso-8859-6 :cp1256))))

(defun guess-gr (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :iso-8859-7 :cp1253))))

(defun guess-ru (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :cp1251 :koi8-u :koi8-r :cp866
                             :iso-8859-2 :iso-8859-5))))

(defun guess-hw (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :iso-8859-8 :cp1255))))

(defun guess-pl (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :cp1250 :iso-8859-2))))

(defun guess-tr (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :iso-8859-9 :cp1254))))

(defun guess-bl (buffer &optional order state)
  (guess (buffer order state (c1) (:utf-8 :iso-8859-13 :cp1257))))

(defun guess-es (buffer &optional order state)
  "Guess for Spanish language"
  (guess (buffer order state (c1) (:iso-8859-1 :utf-8))))

