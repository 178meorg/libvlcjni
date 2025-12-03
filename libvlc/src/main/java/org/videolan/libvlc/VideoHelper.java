package org.videolan.libvlc;

import android.annotation.TargetApi;
import android.app.Activity;
import android.content.res.Configuration;
import android.graphics.PixelFormat;
import android.os.Build;
import android.os.Handler;
import android.util.Log;
import android.view.SurfaceView;
import android.view.TextureView;
import android.view.View;
import android.view.ViewGroup;
import android.view.ViewStub;
import android.widget.FrameLayout;

import org.videolan.R;
import org.videolan.libvlc.interfaces.IMedia;
import org.videolan.libvlc.interfaces.IVLCVout;
import org.videolan.libvlc.util.AndroidUtil;
import org.videolan.libvlc.util.DisplayManager;
import org.videolan.libvlc.util.VLCVideoLayout;

class VideoHelper implements IVLCVout.OnNewVideoLayoutListener {
    private static final String TAG = "LibVLC/VideoHelper";

    private MediaPlayer.ScaleType mCurrentScaleType = MediaPlayer.ScaleType.SURFACE_BEST_FIT;

    private float mCustomScale;
    private boolean mCurrentScaleCustom = false;

    private int mVideoHeight = 0;
    private int mVideoWidth = 0;
    private int mPlaceWidth = 0;
    private int mPlaceHeight = 0;
    private int mPlaceX = 0;
    private int mPlaceY = 0;

    private FrameLayout mVideoSurfaceFrame;
    private SurfaceView mVideoSurface = null;
    private SurfaceView mSubtitlesSurface = null;
    private TextureView mVideoTexture = null;

    private final Handler mHandler = new Handler();
    private View.OnLayoutChangeListener mOnLayoutChangeListener = null;
    private DisplayManager mDisplayManager;

    private org.videolan.libvlc.MediaPlayer mMediaPlayer;

    VideoHelper(MediaPlayer player, VLCVideoLayout surfaceFrame, DisplayManager dm, boolean subtitles, boolean textureView) {
        init(player, surfaceFrame, dm, subtitles, !textureView);
    }

    private void init(MediaPlayer player, VLCVideoLayout surfaceFrame, DisplayManager dm, boolean subtitles, boolean useSurfaceView) {
        mMediaPlayer = player;
        mDisplayManager = dm;
        final boolean isPrimary = mDisplayManager == null || mDisplayManager.isPrimary();
        if (isPrimary) {
            mVideoSurfaceFrame = surfaceFrame.findViewById(R.id.player_surface_frame);
            if (useSurfaceView) {
                ViewStub stub = mVideoSurfaceFrame.findViewById(R.id.surface_stub);
                mVideoSurface = stub != null ? (SurfaceView) stub.inflate() : (SurfaceView) mVideoSurfaceFrame.findViewById(R.id.surface_video);
                if (subtitles) {
                    stub = surfaceFrame.findViewById(R.id.subtitles_surface_stub);
                    mSubtitlesSurface = stub != null ? (SurfaceView) stub.inflate() : (SurfaceView) surfaceFrame.findViewById(R.id.surface_subtitles);
                    mSubtitlesSurface.setZOrderMediaOverlay(true);
                    mSubtitlesSurface.getHolder().setFormat(PixelFormat.TRANSLUCENT);
                }
            } else {
                final ViewStub stub = mVideoSurfaceFrame.findViewById(R.id.texture_stub);
                mVideoTexture = stub != null ? (TextureView) stub.inflate() : (TextureView) mVideoSurfaceFrame.findViewById(R.id.texture_video);;
            }
        } else if (mDisplayManager.getPresentation() != null){
            mVideoSurfaceFrame = mDisplayManager.getPresentation().getSurfaceFrame();
            mVideoSurface = mDisplayManager.getPresentation().getSurfaceView();
            mSubtitlesSurface = mDisplayManager.getPresentation().getSubtitlesSurfaceView();
        }
    }

    void release() {
        if (mMediaPlayer.getVLCVout().areViewsAttached()) detachViews();
        mMediaPlayer = null;
        mVideoSurfaceFrame = null;
        mHandler.removeCallbacks(null);
        mVideoSurface = null;
        mSubtitlesSurface = null;
        mVideoTexture = null;
    }

    void attachViews() {
        if (mVideoSurface == null && mVideoTexture == null) return;
        final IVLCVout vlcVout = mMediaPlayer.getVLCVout();
        if (mVideoSurface != null) {
            vlcVout.setVideoView(mVideoSurface);
            if (mSubtitlesSurface != null)
                vlcVout.setSubtitlesView(mSubtitlesSurface);
        } else if (mVideoTexture != null)
            vlcVout.setVideoView(mVideoTexture);
        else return;
        vlcVout.attachViews(this);

        if (mOnLayoutChangeListener == null) {
            mOnLayoutChangeListener = new View.OnLayoutChangeListener() {
                private final Runnable runnable = new Runnable() {
                    @Override
                    public void run() {
                        if (mVideoSurfaceFrame != null && mOnLayoutChangeListener != null) updateVideoSurfaces();
                    }
                };
                @Override
                public void onLayoutChange(View v, int left, int top, int right,
                                           int bottom, int oldLeft, int oldTop, int oldRight, int oldBottom) {
                    if (left != oldLeft || top != oldTop || right != oldRight || bottom != oldBottom) {
                        mHandler.removeCallbacks(runnable);
                        mHandler.post(runnable);
                    }
                }
            };
        }
        mVideoSurfaceFrame.addOnLayoutChangeListener(mOnLayoutChangeListener);
        mMediaPlayer.setVideoTrackEnabled(true);
        updateVideoDimensions();
    }

    void detachViews() {
        if (mOnLayoutChangeListener != null && mVideoSurfaceFrame != null) {
            mVideoSurfaceFrame.removeOnLayoutChangeListener(mOnLayoutChangeListener);
            mOnLayoutChangeListener = null;
        }
        mMediaPlayer.setVideoTrackEnabled(false);
        mMediaPlayer.getVLCVout().detachViews();
    }

    private void changeMediaPlayerLayout() {
        if (mMediaPlayer.isReleased()) return;

        if (mCurrentScaleCustom) {
            mMediaPlayer.setAspectRatio(null);
            mMediaPlayer.setNativeScale(mCustomScale);
            mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.None);
            return;
        }

        /* Change the video placement using the MediaPlayer API */
        switch (mCurrentScaleType) {
            case SURFACE_BEST_FIT:
                mMediaPlayer.setAspectRatio(null);
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_FIT_SCREEN:
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setAspectRatio(null);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Larger);
                break;
            case SURFACE_FILL:
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setAspectRatio("fill");
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_16_9:
                mMediaPlayer.setAspectRatio("16:9");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_16_10:
                mMediaPlayer.setAspectRatio("16:10");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_2_1:
                mMediaPlayer.setAspectRatio("2:1");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_221_1:
                mMediaPlayer.setAspectRatio("221:100");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_235_1:
                mMediaPlayer.setAspectRatio("235:100");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_239_1:
                mMediaPlayer.setAspectRatio("239:100");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_5_4:
                mMediaPlayer.setAspectRatio("5:4");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_4_3:
                mMediaPlayer.setAspectRatio("4:3");
                mMediaPlayer.setNativeScale(0);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.Smaller);
                break;
            case SURFACE_ORIGINAL:
                mMediaPlayer.setAspectRatio(null);
                mMediaPlayer.setNativeScale(1);
                mMediaPlayer.setDisplayFit(MediaPlayer.FitMode.None);
                break;
        }
    }

    void updateVideoDimensions() {
        if (mMediaPlayer == null || mMediaPlayer.isReleased() || !mMediaPlayer.getVLCVout().areViewsAttached())
            return;
        final boolean isPrimary = mDisplayManager == null || mDisplayManager.isPrimary();
        final Activity activity = !isPrimary ? null : AndroidUtil.resolveActivity(mVideoSurfaceFrame.getContext());

        final int surfaceWidth;
        final int surfaceHeight;

        // get screen size
        if (activity != null) {
            surfaceWidth = mVideoSurfaceFrame.getWidth();
            surfaceHeight = mVideoSurfaceFrame.getHeight();
        } else if (mDisplayManager != null && mDisplayManager.getPresentation() != null && mDisplayManager.getPresentation().getWindow() != null) {
            surfaceWidth = mDisplayManager.getPresentation().getWindow().getDecorView().getWidth();
            surfaceHeight = mDisplayManager.getPresentation().getWindow().getDecorView().getHeight();
        } else return;

        // sanity check
        if (surfaceWidth * surfaceHeight == 0) {
            Log.e(TAG, "Invalid surface size");
            return;
        }

        mMediaPlayer.getVLCVout().setWindowSize(surfaceWidth, surfaceHeight);
    }

    void updateVideoSurfaces() {
        if (mMediaPlayer == null || mMediaPlayer.isReleased() || !mMediaPlayer.getVLCVout().areViewsAttached()) return;
        final boolean isPrimary = mDisplayManager == null || mDisplayManager.isPrimary();
        final Activity activity = !isPrimary ? null : AndroidUtil.resolveActivity(mVideoSurfaceFrame.getContext());

        /* We will setup either the videoSurface or the videoTexture */
        View videoView = mVideoSurface;
        if (videoView == null)
            videoView = mVideoTexture;

        ViewGroup.LayoutParams lp = videoView.getLayoutParams();
        if (mPlaceWidth * mPlaceHeight == 0 || (AndroidUtil.isNougatOrLater && activity != null && activity.isInPictureInPictureMode())) {
            changeMediaPlayerLayout();
            /* Case of OpenGL vouts: handles the placement of the video using MediaPlayer API */
            lp.width  = ViewGroup.LayoutParams.MATCH_PARENT;
            lp.height = ViewGroup.LayoutParams.MATCH_PARENT;
            videoView.setLayoutParams(lp);
            lp = mVideoSurfaceFrame.getLayoutParams();
            lp.width  = ViewGroup.LayoutParams.MATCH_PARENT;
            lp.height = ViewGroup.LayoutParams.MATCH_PARENT;
            mVideoSurfaceFrame.setLayoutParams(lp);
            return;
        }

        // set display size
        lp.width  = mPlaceWidth;
        lp.height = mPlaceHeight;
        videoView.setLayoutParams(lp);

        videoView.invalidate();
    }

    @Override
    public void onNewVideoLayout(IVLCVout vlcVout, int displayWidth, int displayHeight,
                                 int placeWidth, int placeHeight, int placeX, int placeY) {
        mPlaceWidth = placeWidth;
        mPlaceHeight = placeHeight;
        mPlaceX = placeX;
        mPlaceY = placeY;
        if (placeWidth == 0 || placeHeight == 0) {
            mVideoWidth = mVideoHeight = 0;
        } else {
            mVideoWidth = displayWidth;
            mVideoHeight = displayHeight;
        }
        updateVideoSurfaces();
    }

    void setVideoScale(MediaPlayer.ScaleType type) {
        mCurrentScaleType = type;
        mCurrentScaleCustom = false;
        changeMediaPlayerLayout();
    }

    void setCustomScale(float scale) {
        mCustomScale = scale;
        mCurrentScaleCustom = true;
        changeMediaPlayerLayout();
    }

    MediaPlayer.ScaleType getVideoScale() {
        return mCurrentScaleType;
    }
}
