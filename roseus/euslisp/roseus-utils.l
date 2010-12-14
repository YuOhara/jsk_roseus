;; this is a collection of utility functions and macros
;; for ros<->euslisp interface

;; Sensors

(ros::roseus-add-msgs "sensor_msgs")

(defun make-camera-from-ros-camera-info-aux (pwidth pheight p frame-coords)
  (let* ((b (body+ (make-cube 40 30 30)
                   (send (make-cylinder 2 30) :rotate pi/2 :x)
                   (make-cylinder 13 25)))
         (fx (elt p 0))(fy (elt p 5))
         (cx (elt p 2))(cy (elt p 6))
         (tx (elt p 3))(ty (elt p 7))
         c (vd 1.0))
    (setq c (instance camera-model :init b :width pwidth :height pheight
                      :viewdistance vd))
    (send (c . vwing) :screen (/ (* vd pwidth 0.5) fx) (/ (* vd pheight 0.5) fy))
    (send c :newprojection
          (make-matrix 4 4
                       (list (float-vector fx  0 cx (* fx tx))
                             (float-vector  0 fy cy (* fy ty))
                             (float-vector  0  0  1  0)
                             (float-vector  0  0  0  1))))
    (send c :newcoords (send frame-coords :copy-worldcoords))
    (send c :translate (float-vector (- tx) (- ty) 0))
    (send (c . vwing) :translate (float-vector tx ty 0))
    (send frame-coords :assoc c)
    c))

(defun make-camera-from-ros-camera-info (msg)
  (let ((pwidth (send msg :width))
        (pheight (send msg :height))
        (p (send msg :P)))
    (make-camera-from-ros-camera-info-aux pwidth pheight p)))

;;
;; Visualization
;;
(ros::roseus-add-msgs "visualization_msgs")

;; ros helper

(defun vector->rgba (cv &optional (alpha 1.0))
  (if (vectorp cv)
      (instance std_msgs::ColorRGBA :init
                :r (elt cv 0)
                :g (elt cv 1)
                :b (elt cv 2)
                :a alpha)
    (instance std_msgs::ColorRGBA :init
              :r 0 :g 0 :b 0 :a alpha)))

;; eus shape object -> visualization_msgs::Marker

(defun cylinder->marker-msg (cyl header
				 &key ((:color col) (float-vector 1.0 0 0))
				      ((:alpha a) 1.0)
                                      ((:id idx) 0))
  (let ((msg (instance visualization_msgs::Marker :init
                       :type visualization_msgs::CYLINDER
                       :header header
                       :id idx))
        (cent-coords (send cyl :copy-worldcoords))
        (height (height-of-cylinder cyl))
        (radius (radius-of-cylinder cyl)))
    (send cent-coords :translate (float-vector 0 0 (/ height 2)))
    (send msg :pose (ros::coords->tf-pose cent-coords))
    (send msg :scale (ros::pos->tf-translation
                      (float-vector (* 2 radius) (* 2 radius) height)))
    (send msg :color (vector->rgba col a))
    msg))

(defun cube->marker-msg (cb header
			    &key ((:color col) (float-vector 1.0 0 0))
   			         ((:alpha a) 1.0)
                                 ((:id idx) 0))
  (let ((msg (instance visualization_msgs::Marker :init
                       :type visualization_msgs::CUBE
                       :header header
                       :id idx))
        (cent-coords (send cb :copy-worldcoords))
        (cx (x-of-cube cb))
        (cy (y-of-cube cb))
        (cz (z-of-cube cb)))
    (send msg :pose (ros::coords->tf-pose cent-coords))
    (send msg :scale (ros::pos->tf-translation
                      (float-vector cx cy cz)))
    (send msg :color (vector->rgba col a))
    msg))

(defun sphere->marker-msg (sp header
			    &key ((:color col) (float-vector 1.0 0 0))
   			         ((:alpha a) 1.0)
                                 ((:id idx) 0))
  (let ((msg (instance visualization_msgs::Marker :init
                       :type visualization_msgs::SPHERE
                       :header header
                       :id idx))
        (cent-coords (send sp :copy-worldcoords))
        (r (radius-of-sphere sp)))
    (send msg :pose (ros::coords->tf-pose cent-coords))
    (send msg :scale (ros::pos->tf-translation
                      (scale 2.0 (float-vector r r r))))
    (send msg :color (vector->rgba col a))
    msg))

(defun faces->marker-msg (faces header &key
                                ((:color col) (float-vector 1 0 0))
                                ((:id idx) 0))
  (let* ((tri-faces
          (mapcan #'(lambda (f) (geo::face-to-triangle f))
                  faces))
         (tri-vertices
          (mapcan #'(lambda (f) (cdr (send f :vertices)))
                  tri-faces))
         (points
          (mapcar #'(lambda (p)
                      (ros::pos->tf-point p))
                  tri-vertices))
         (msg (instance visualization_msgs::Marker :init
                        :type visualization_msgs::TRIANGLE_LIST
                        :header header
                        :id idx)))
    (send msg :pose (ros::coords->tf-pose (make-coords)))
    (send msg :scale (ros::pos->tf-translation
                      (float-vector 1000 1000 1000)))
    (send msg :color (vector->rgba (float-vector 1 0 0) 1.0))

    (send msg :points points)
    msg))

(defun object->marker-msg (obj header &key
                               ((:color col) (float-vector 1 1 1))
                               ((:id idx) 0))
  (let ((bodies (send obj :bodies)))
    (when (and bodies (listp bodies))
      (let* ((msg (instance visualization_msgs::Marker :init
                           :type visualization_msgs::TRIANGLE_LIST
                           :header header
                           :id idx))
             (body-colors
              (mapcar
               #'(lambda (b)
                   (cond ((null (get b :face-color)) col)
                         (t (gl::find-color (get b :face-color)))))
               bodies))
             (triface-vertices-list
              (mapcar #'(lambda (fs)
                          (mapcan #'(lambda (f) (cdr (send f :vertices)))
                                  (send fs :faces)))
                      (mapcar #'body-to-faces bodies)))
             (color-list
              (mapcar #'(lambda (vlist c)
                          (if (derivedp c gl::colormaterial) (setq c (send c :diffuse))) ;; jsk
                          (make-list (length vlist) :initial-element c))
                      triface-vertices-list body-colors))
             (points
              (mapcar #'(lambda (v)
                          (ros::pos->tf-point v))
                      (apply #'append triface-vertices-list)))
             (colors
              (mapcar #'(lambda (c)
                          (if (derivedp c gl::colormaterial) (setq c (send c :diffuse))) ;; jsk
                          (vector->rgba c 1.0))
                      (apply #'append color-list)))
             )
        (send msg :frame_locked t)
        (send msg :pose (ros::coords->tf-pose (send obj :worldcoords)))
        (send msg :scale (ros::pos->tf-translation
                          (float-vector 1000 1000 1000)))
        (send msg :points points)
        (send msg :color  (vector->rgba (float-vector 0 0 0) 1.0))
        (send msg :colors colors)
        msg))))

(defun coords->marker-msg (coords header &key (size 1) (width 1) (id 0))
  (let* ((msg (instance visualization_msgs::Marker :init
                        :type visualization_msgs::LINE_LIST
                        :header header
                        :id id))
         (points (mapcar #'(lambda (p)
                             (ros::pos->tf-point (scale (* 100 size) p)))
                         (list (float-vector 0 0 0)
                               (float-vector 1 0 0)
                               (float-vector 0 0 0)
                               (float-vector 0 1 0)
                               (float-vector 0 0 0)
                               (float-vector 0 0 1))))
         (colors (mapcar #'(lambda (c) (vector->rgba c 1.0))
                         (list (float-vector 1 0 0) (float-vector 1 0 0)
                               (float-vector 0 1 0) (float-vector 0 1 0)
                               (float-vector 0 0 1) (float-vector 0 0 1)))))
    (send msg :pose (ros::coords->tf-pose coords))
    (send msg :scale (ros::pos->tf-translation
                      (float-vector width 0 0)))
    (send msg :points points)
    (send msg :color  (vector->rgba (float-vector 0 0 0) 1.0))
    (send msg :colors colors)
    msg))

;; visualization_msgs::Marker -> eus shape object

(defun marker-msg->shape (msg)
  (let ((type (send msg :type)))
    (print type)
    (print (numberp type))
    (case type
      (visualization_msgs::CUBE     (marker-msg->shape/cube msg))
      (visualization_msgs::CYLINDER (marker-msg->shape/cylinder msg))
      (visualization_msgs::SPHERE   (marker-msg->shape/sphere msg))
      )))

(defun marker-msg->shape/cube (msg)
  (let* ((scale (ros::tf-point->pos (send msg :scale)))
         (rgba (send msg :color))
         (cb (make-cube (elt scale 0) (elt scale 1) (elt scale 2)
                        :coords (ros::tf-pose->coords (send msg :pose)))))
    (setf (get cb :face-color)
          (float-vector (send rgba :r)
                        (send rgba :g)
                        (send rgba :b)))
    (gl::transparent cb (send rgba :a))
    cb))

(defun marker-msg->shape/cylinder (msg)
  (let* ((scale (ros::tf-point->pos (send msg :scale)))
         (rgba (send msg :color))
         (radius (/ (elt scale 0) 2.0))
         (height (elt scale 2))
         (cyl (make-cylinder radius
                             height
                             :coords (ros::tf-pose->coords (send msg :pose)))))
    (send cyl :translate (float-vector 0 0 (- (/ height 2.0))))
    (setf (get cyl :face-color)
          (float-vector (send rgba :r)
                        (send rgba :g)
                        (send rgba :b)))
    (gl::transparent cyl (send rgba :a))
    cyl))

(defun marker-msg->shape/sphere (msg)
  (let* ((scale (ros::tf-point->pos (send msg :scale)))
         (rgba (send msg :color))
         (sp (make-sphere (/ (elt scale 0) 2.0)
                          :coords (ros::tf-pose->coords (send msg :pose)))))
    (setf (get sp :face-color)
          (float-vector (send rgba :r)
                        (send rgba :g)
                        (send rgba :b)))
    (gl::transparent sp (send rgba :a))
    sp))
