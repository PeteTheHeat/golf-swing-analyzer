# Model cache

The desktop analyzer downloads the Google MediaPipe Pose Landmarker Full task file on the
first analysis run. The model is stored in the user cache by default and is not
committed to this repository.

Pass `--model /path/to/pose_landmarker.task` to use a model that you already
downloaded.
