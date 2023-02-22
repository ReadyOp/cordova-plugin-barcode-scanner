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

import android.util.Log;
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
import androidx.camera.core.FocusMeteringAction;
import androidx.camera.core.MeteringPoint;
import androidx.camera.core.SurfaceOrientedMeteringPointFactory;
import androidx.camera.lifecycle.ProcessCameraProvider;
import androidx.camera.mlkit.vision.MlKitAnalyzer;
import androidx.camera.view.LifecycleCameraController;
import androidx.camera.view.PreviewView;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import androidx.lifecycle.LifecycleOwner;
import androidx.lifecycle.LiveData;

import com.google.android.gms.common.api.CommonStatusCodes;
import com.google.android.material.snackbar.Snackbar;
import com.google.common.util.concurrent.ListenableFuture;
import com.google.mlkit.vision.barcode.BarcodeScanner;
import com.google.mlkit.vision.barcode.BarcodeScannerOptions;
import com.google.mlkit.vision.barcode.BarcodeScanning;
import com.google.mlkit.vision.barcode.common.Barcode;

import java.nio.charset.StandardCharsets;
import java.util.Arrays;
import java.util.List;
import java.util.Objects;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.TimeUnit;

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
  private ImageButton _CloseButton;
  private LifecycleCameraController cameraController;

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

      LiveData<Integer> flashState = cameraController.getCameraInfo().getTorchState();
      if (flashState.getValue() != null) {
        boolean state = flashState.getValue() == 1;
        _TorchButton.setBackgroundResource(getResources().getIdentifier(!state ? "torch_active" : "torch_inactive",
          "drawable", CaptureActivity.this.getPackageName()));
        cameraController.getCameraControl().enableTorch(!state);
      }

    });

    _CloseButton = findViewById(getResources().getIdentifier("close_button", "id", this.getPackageName()));

    _CloseButton.setOnClickListener(v -> {
      finish();
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

      if (cameraController != null) {
        float ratio = Objects.requireNonNull(cameraController.getCameraInfo().getZoomState().getValue()).getZoomRatio();
        float scale = ratio * detector.getScaleFactor();
        cameraController.getCameraControl().setZoomRatio(scale);
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
      DrawFocusRect(Color.parseColor("#FFFFFF"), null, null);
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
    DrawFocusRect(Color.parseColor("#FFFFFF"), null, null);
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

  @Override
  protected void onStop() {
    super.onStop();

    if (this.cameraController != null) {
      this.cameraController.getCameraControl().cancelFocusAndMetering();
    }
  }

  @SuppressLint("ClickableViewAccessibility")
  void startCamera() {
    mCameraView = findViewById(getResources().getIdentifier("previewView", "id", getPackageName()));
    mCameraView.setImplementationMode(PreviewView.ImplementationMode.PERFORMANCE);

    boolean rotateCamera = getIntent().getBooleanExtra("rotateCamera", false);
    if (rotateCamera) {
      mCameraView.setScaleX(-1F);
      mCameraView.setScaleY(-1F);
    } else {
      mCameraView.setScaleX(1F);
      mCameraView.setScaleY(1F);
    }

    mCameraView.addOnLayoutChangeListener((v, left, top, right, bottom, oldLeft, oldTop, oldRight, oldBottom) -> {
      // If the camera isn't ready yet (hasn't been bound to the preview view)
      if (this.cameraController == null) {
        return;
      }
      MeteringPoint autoFocusPoint = new SurfaceOrientedMeteringPointFactory(1f, 1f).createPoint(.5f, .5f);

      FocusMeteringAction.Builder builder = new FocusMeteringAction.Builder(autoFocusPoint);
      builder.setAutoCancelDuration(3, TimeUnit.SECONDS);

      FocusMeteringAction autoFocusAction = builder.build();
      cameraController.getCameraControl().cancelFocusAndMetering();
      cameraController.getCameraControl().startFocusAndMetering(autoFocusAction);
    });

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
    cameraController = new LifecycleCameraController(getBaseContext());

    int barcodeFormat;
    if (BarcodeFormats == 0 || BarcodeFormats == 1234) {
      barcodeFormat = (Barcode.FORMAT_CODE_39 | Barcode.FORMAT_DATA_MATRIX);
    } else {
      barcodeFormat = BarcodeFormats;
    }

    BarcodeScanner scanner = BarcodeScanning.getClient(new BarcodeScannerOptions.Builder().setBarcodeFormats(barcodeFormat).build());

    cameraController.setTapToFocusEnabled(true);
    cameraController.setImageAnalysisAnalyzer(executor, new MlKitAnalyzer(
      Arrays.asList(scanner), cameraController.COORDINATE_SYSTEM_VIEW_REFERENCED, executor, result -> {

      List<Barcode> results = result.getValue(scanner);

      if ((results == null) || (results.size() == 0) || (results.get(0) == null)) {
        DrawFocusRect(Color.parseColor("#FFFFFF"), null, null);
        return;
      }

      if (results.size() > 0) {
        for (Barcode barcode : results) {
          DrawFocusRect(Color.parseColor("#FFFFFF"), null, barcode);

          if (barcode.getFormat() == Barcode.FORMAT_PDF417) {
            Barcode.DriverLicense dl = barcode.getDriverLicense();
            String firstName = dl.getFirstName();
            Log.d("ReadyOpScanner", "First Name: " + firstName);
          }

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
    }));

    cameraController.bindToLifecycle((LifecycleOwner) this);
    mCameraView.setController(cameraController);
  }

  /**
   * For drawing the rectangular box
   */
  private void DrawFocusRect(int color, Bitmap preview, Barcode barcode) {
    if (mCameraView == null) {
      return;
    }

    boolean isCard = this.detectorType.equals("card");

    float height = mCameraView.getHeight();
    float width = mCameraView.getWidth();

    float diameterW = (float)(width * (isCard ? .84 : .75));
    float diameterH = (float)(diameterW * (isCard ? .46 : 1));

    Canvas canvas = holder.lockCanvas();
    if (canvas == null) {
      return;
    }

    canvas.drawColor(0, PorterDuff.Mode.CLEAR);

    // border's properties
    Paint paint = new Paint();
    paint.setStyle(Paint.Style.STROKE);
    paint.setColor(color);
    paint.setStrokeWidth(5);

    if (preview != null) {
      canvas.drawBitmap(preview, 0, 0, paint);
    }

    float left = width / 2 - diameterW / 2;
    float top = height / 2 - diameterH / 2;
    float right = width / 2 + diameterW / 2;
    float bottom = height / 2 + diameterH / 2;

    if (this.reticleRect == null) {
      this.reticleRect = new RectF(left, top, right, bottom);
    }

    if (barcode != null) {
      Paint boundingRectPaint = new Paint();
      boundingRectPaint.setStyle(Paint.Style.STROKE);
      boundingRectPaint.setColor(Color.YELLOW);
      boundingRectPaint.setStrokeWidth(5.0f);
      boundingRectPaint.setAlpha(200);
      canvas.drawRect(barcode.getBoundingBox(), boundingRectPaint);
    }

    canvas.drawRoundRect(this.reticleRect, 50, 50, paint);

    // Draw the reticle line
    paint.setARGB((int)(255 * 0.40), 255, 0, 0);
    paint.setStyle(Paint.Style.FILL);
    canvas.drawLine((left + 5), (float)((height / 2) - 2.5), (right - 10), (float)((height / 2) + 2.5), paint);

    holder.unlockCanvasAndPost(canvas);
  }
}
