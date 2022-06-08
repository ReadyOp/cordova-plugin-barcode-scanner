package com.readyop.cordova.plugins.barcode.scanner;

import android.Manifest;
import android.annotation.SuppressLint;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.graphics.Color;
import android.graphics.Paint;
import android.graphics.PixelFormat;
import android.graphics.PorterDuff;
import android.graphics.RectF;
import android.os.Bundle;

import android.util.Size;
import android.view.GestureDetector;
import android.view.MotionEvent;
import android.view.ScaleGestureDetector;
import android.view.SurfaceHolder;
import android.view.SurfaceView;
import android.view.View;
import android.widget.ImageButton;

import androidx.annotation.NonNull;
import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.camera.core.Camera;
import androidx.camera.core.CameraSelector;
import androidx.camera.core.ImageAnalysis;
import androidx.camera.core.Preview;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LiveData;

import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.gms.tasks.Task;
import com.google.android.material.snackbar.Snackbar;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.Barcode;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.common.InputImage;
import com.readyop.cordova.plugins.barcode.scanner.utils.BitmapUtils;

import java.nio.charset.StandardCharsets;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

public class CaptureActivity extends AppCompatActivity implements SurfaceHolder.Callback {

  public Integer BarcodeFormats;
  public String detectorType = "";

  public static final String BarcodeFormat = "MLKitBarcodeFormat";
  public static final String BarcodeType = "MLKitBarcodeType";
  public static final String BarcodeValue = "MLKitBarcodeValue";

  private ListenableFuture<ProcessCameraProvider> cameraProviderFuture;
  private final ExecutorService executor = Executors.newSingleThreadExecutor();
  private PreviewView mCameraView;
  private SurfaceHolder holder;
  private SurfaceView surfaceView;
  private RectF reticleRect;

  private static final int RC_HANDLE_CAMERA_PERM = 2;
  private ImageButton _TorchButton;
  private Camera camera;

  private ScaleGestureDetector _ScaleGestureDetector;
  private GestureDetector _GestureDetector;

  @Override
  protected void onCreate(Bundle savedInstanceState) {
    super.onCreate(savedInstanceState);
    setContentView(getResources().getIdentifier("capture_activity", "layout", getPackageName()));

    // Create the bounding box
    surfaceView = findViewById(getResources().getIdentifier("overlay", "id", getPackageName()));
    surfaceView.setZOrderOnTop(true);

    holder = surfaceView.getHolder();
    holder.setFormat(PixelFormat.TRANSPARENT);
    holder.addCallback(this);

    // read parameters from the intent used to launch the activity.
    BarcodeFormats = getIntent().getIntExtra("formats", 1234);
    detectorType = getIntent().getStringExtra("detectorType");

    if (!detectorType.equals("card")) {
      detectorType = "";
    }

    int rc = ActivityCompat.checkSelfPermission(this, Manifest.permission.CAMERA);

    if (rc == PackageManager.PERMISSION_GRANTED) {
      // Start Camera
      startCamera();
    } else {
      requestCameraPermission();
    }

    _GestureDetector = new GestureDetector(this, new CaptureGestureListener());
    _ScaleGestureDetector = new ScaleGestureDetector(this, new ScaleListener());

    _TorchButton = findViewById(getResources().getIdentifier("torch_button", "id", this.getPackageName()));
    if (!getIntent().getBooleanExtra("detectorType", true)) {
      _TorchButton.setVisibility(View.INVISIBLE);
    }

    _TorchButton.setOnClickListener(v -> {

      LiveData<Integer> flashState = camera.getCameraInfo().getTorchState();
      if (flashState.getValue() != null) {
        boolean state = flashState.getValue() == 1;
        _TorchButton.setBackgroundResource(getResources().getIdentifier(!state ? "torch_active" : "torch_inactive",
            "drawable", CaptureActivity.this.getPackageName()));
        camera.getCameraControl().enableTorch(!state);
      }

    });

  }

  // ----------------------------------------------------------------------------
  // | Helper classes
  // ----------------------------------------------------------------------------
  private static class CaptureGestureListener extends GestureDetector.SimpleOnGestureListener {
    @Override
    public boolean onSingleTapConfirmed(MotionEvent e) {
      return super.onSingleTapConfirmed(e);
    }
  }

  private class ScaleListener implements ScaleGestureDetector.OnScaleGestureListener {
    @Override
    public boolean onScale(ScaleGestureDetector detector) {
      return false;
    }

    @Override
    public boolean onScaleBegin(ScaleGestureDetector detector) {
      return true;
    }

    @Override
    public void onScaleEnd(ScaleGestureDetector detector) {

      if (camera != null) {
        float ratio = Objects.requireNonNull(camera.getCameraInfo().getZoomState().getValue()).getZoomRatio();
        float scale = ratio * detector.getScaleFactor();
        camera.getCameraControl().setZoomRatio(scale);
      }
    }
  }

  private void requestCameraPermission() {

    final String[] permissions = new String[] { Manifest.permission.CAMERA,
        Manifest.permission.WRITE_EXTERNAL_STORAGE };

    boolean shouldShowPermission = !ActivityCompat.shouldShowRequestPermissionRationale(this,
        Manifest.permission.CAMERA);
    shouldShowPermission = shouldShowPermission
        && !ActivityCompat.shouldShowRequestPermissionRationale(this, Manifest.permission.WRITE_EXTERNAL_STORAGE);

    if (shouldShowPermission) {
      ActivityCompat.requestPermissions(this, permissions, RC_HANDLE_CAMERA_PERM);
      return;
    }

    View.OnClickListener listener = view -> ActivityCompat.requestPermissions(CaptureActivity.this, permissions,
        RC_HANDLE_CAMERA_PERM);

    findViewById(getResources().getIdentifier("topLayout", "id", getPackageName())).setOnClickListener(listener);
    Snackbar
        .make(surfaceView, getResources().getIdentifier("permission_camera_rationale", "string", getPackageName()),
            Snackbar.LENGTH_INDEFINITE)
        .setAction(getResources().getIdentifier("ok", "string", getPackageName()), listener).show();

  }

  @Override
  public void onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
    if (requestCode != RC_HANDLE_CAMERA_PERM) {
      super.onRequestPermissionsResult(requestCode, permissions, grantResults);
      return;
    }

    if (grantResults.length != 0 && grantResults[0] == PackageManager.PERMISSION_GRANTED) {
      startCamera();
      DrawFocusRect(Color.parseColor("#FFFFFF"));
      return;
    }

    DialogInterface.OnClickListener listener = (dialog, id) -> finish();

    AlertDialog.Builder builder = new AlertDialog.Builder(this);
    builder.setTitle("Camera permission required")
        .setMessage(getResources().getIdentifier("no_camera_permission", "string", getPackageName()))
        .setPositiveButton(getResources().getIdentifier("ok", "string", getPackageName()), listener).show();
  }

  @Override
  public void surfaceCreated(SurfaceHolder surfaceHolder) {

  }

  @Override
  public void surfaceChanged(SurfaceHolder surfaceHolder, int i, int i1, int i2) {
    DrawFocusRect(Color.parseColor("#FFFFFF"));
  }

  @Override
  public void surfaceDestroyed(SurfaceHolder surfaceHolder) {

  }

  @Override
  public boolean onTouchEvent(MotionEvent e) {
    boolean b = _ScaleGestureDetector.onTouchEvent(e);
    boolean c = _GestureDetector.onTouchEvent(e);

    return b || c || super.onTouchEvent(e);
  }

  @Override
  protected void onPause() {
    super.onPause();

  }

  @Override
  protected void onResume() {
    super.onResume();

  }

  void startCamera() {
    mCameraView = findViewById(getResources().getIdentifier("previewView", "id", getPackageName()));
    mCameraView.setPreferredImplementationMode(PreviewView.ImplementationMode.TEXTURE_VIEW);

    boolean rotateCamera = getIntent().getBooleanExtra("rotateCamera", false);
    if (rotateCamera) {
      mCameraView.setScaleX(-1F);
      mCameraView.setScaleY(-1F);
    } else {
      mCameraView.setScaleX(1F);
      mCameraView.setScaleY(1F);
    }

    // mCameraView.setScaleType(PreviewView.ScaleType.FIT_CENTER);

    cameraProviderFuture = ProcessCameraProvider.getInstance(this);
    cameraProviderFuture.addListener(() -> {
      try {
        ProcessCameraProvider cameraProvider = cameraProviderFuture.get();
        CaptureActivity.this.bindPreview(cameraProvider);

      } catch (ExecutionException | InterruptedException e) {
        // No errors need to be handled for this Future.
        // This should never be reached.
      }
    }, ContextCompat.getMainExecutor(this));
  }

  /**
   * Binding to camera
   */
  @SuppressLint("UnsafeOptInUsageError")
  private void bindPreview(ProcessCameraProvider cameraProvider) {

    int barcodeFormat;
    if (BarcodeFormats == 0 || BarcodeFormats == 1234) {
      barcodeFormat = (Barcode.FORMAT_CODE_39 | Barcode.FORMAT_DATA_MATRIX);
    } else {
      barcodeFormat = BarcodeFormats;
    }

    Preview preview = new Preview.Builder().build();

    CameraSelector cameraSelector = new CameraSelector.Builder().requireLensFacing(CameraSelector.LENS_FACING_BACK)
        .build();

    preview.setSurfaceProvider(mCameraView.createSurfaceProvider());

    ImageAnalysis.Builder builder = new ImageAnalysis.Builder();
    builder.setBackpressureStrategy(ImageAnalysis.STRATEGY_KEEP_ONLY_LATEST);
    builder.setTargetResolution(new Size(mCameraView.getWidth(), mCameraView.getHeight()));

    ImageAnalysis imageAnalysis = builder.build();

    BarcodeScanner scanner = BarcodeScanning.getClient(new BarcodeScannerOptions.Builder().setBarcodeFormats(barcodeFormat).build());

    imageAnalysis.setAnalyzer(executor, image -> {
      if (image.getImage() == null) {
        return;
      }

      Bitmap bmp = BitmapUtils.getBitmap(image);
      if (bmp == null) {
        return;
      }
      int boxHeight = (int)(this.reticleRect.bottom - this.reticleRect.top);
      int boxWidth = (int)(this.reticleRect.right - this.reticleRect.left);

      // Crop the image to just the scanner reticle
      Bitmap bitmap = Bitmap.createBitmap(bmp, (int)this.reticleRect.left, (int)this.reticleRect.top, boxWidth, boxHeight);

      Task<List<Barcode>> task = scanner.process(InputImage.fromBitmap(bitmap, image.getImageInfo().getRotationDegrees()));
      task.addOnSuccessListener(barCodes -> {
        // # Code to test image viewfinder
        /*
         * ImageView imageView = (ImageView)
         * findViewById(getResources().getIdentifier("imageView", "id",
         * getPackageName())); imageView.setImageBitmap(bitmap);
         */
        if (barCodes.size() > 0) {
          for (Barcode barcode : barCodes) {
            // Toast.makeText(CaptureActivity.this, "FOUND: " + barcode.getDisplayValue(),
            // Toast.LENGTH_SHORT).show();
            Intent data = new Intent();
            String value = barcode.getRawValue();

            // rawValue returns null if string is not UTF-8 encoded.
            // If that's the case, we will decode it as ASCII,
            // because it's the most common encoding for barcodes.
            // e.g. https://www.barcodefaq.com/1d/code-128/
            if (barcode.getRawValue() == null) {
              value = new String(barcode.getRawBytes(), StandardCharsets.US_ASCII);
            }

            data.putExtra(BarcodeFormat, barcode.getFormat());
            data.putExtra(BarcodeType, barcode.getValueType());
            data.putExtra(BarcodeValue, value);
            setResult(CommonStatusCodes.SUCCESS, data);
            finish();
          }
        }
      });
      task.addOnFailureListener(e -> {
      });
      task.addOnCompleteListener(r -> image.close());
    });

    camera = cameraProvider.bindToLifecycle((LifecycleOwner) this, cameraSelector, imageAnalysis, preview);
  }

  /**
   * For drawing the rectangular box
   */
  private void DrawFocusRect(int color) {
    if (mCameraView == null) {
      return;
    }
    boolean isCard = this.detectorType.equals("card");

    float height = mCameraView.getHeight();
    float width = mCameraView.getWidth();
    float diameterW = (float)(width * (isCard ? .85 : .75));
    float diameterH = (float)(diameterW * (isCard ? .5 : 1));

    Canvas canvas = holder.lockCanvas();
    canvas.drawColor(0, PorterDuff.Mode.CLEAR);

    // border's properties
    Paint paint = new Paint();
    paint.setStyle(Paint.Style.STROKE);
    paint.setColor(color);
    paint.setStrokeWidth(5);

    float left = width / 2 - diameterW / 2;
    float top = height / 2 - diameterH / 2;
    float right = width / 2 + diameterW / 2;
    float bottom = height / 2 + diameterH / 2;

    this.reticleRect = new RectF (left, top, right, bottom);
    canvas.drawRoundRect(this.reticleRect, 50, 50, paint);

    // Draw the reticle line
    paint.setARGB((int)(255 * 0.40), 255, 0, 0);
    paint.setStyle(Paint.Style.FILL);
    canvas.drawLine((left + 5), (float)((height / 2) - 2.5), (right - 10), (float)((height / 2) + 2.5), paint);

    holder.unlockCanvasAndPost(canvas);
  }
}
