const exec = cordova.require('cordova/exec');

/**
 * Barcode formats
 *
 * @type Object
 */
const formats = {
    Code128: true,
    Code39: true,
    Code93: true,
    CodaBar: true,
    DataMatrix: true,
    EAN13: true,
    EAN8: true,
    ITF: true,
    QRCode: true,
    UPCA: true,
    UPCE: true,
    PDF417: false,
    Aztec: true,
};

/**
 * Barcode format codes
 */
const formatCodes = {
    Code128: 1,
    Code39: 2,
    Code93: 4,
    CodaBar: 8,
    DataMatrix: 16,
    EAN13: 32,
    EAN8: 64,
    ITF: 128,
    QRCode: 256,
    UPCA: 512,
    UPCE: 1024,
    PDF417: 2048,
    Aztec: 4096,
};

/**
 * Default config options
 */
const defaults = {
    beepOnSuccess: false,
    detectorType: null, // [ null | 'card' ]
    formats: formats,
    rotateCamera: false, // Android only
    showFlipCameraButton: false, // iOS only
    showTorchButton: true,
    vibrateOnSuccess: false,
};

/**
 * Constructor.
 *
 * @returns {BarcodeScanner}
 */
class BarcodeScanner
{
    /**
     * Get the barcode format, as a string, from it's number value
     */
    getBarcodeFormat(code)
    {
        return Object.keys(formatCodes).find((k) => formatCodes[k] === code);
    }

    /**
     * Start the scanning process
     */
    scan(config, onSuccess, onError)
    {
        if (config instanceof Array || typeof(config) !== 'object') {
            config = defaults;
        }
        if (!onError) {
            onError = () => {};
        }

        if (typeof(onError) !== 'function') {
            console.log('BarcodeScanner.scan error: Error callback must be a function.');
            return;
        }
        if (typeof(onSuccess) !== "function") {
            console.log('BarcodeScanner.scan error: Success callback must be a function.');
            return;
        }

        // Setup the config properties
        config = Object.assign({}, defaults, config);

        let formats = 0;
        for (const [ format, enabled ] of Object.entries(config.formats)) {
            if (enabled) {
                formats += formatCodes[format];
            }
        }
        config.formats = formats;

        exec(
            (r) => {
                const [text, format] = r;

                onSuccess({
                    text: text,
                    format: this.getBarcodeFormat(format),
                });
            },
            (e) => {
                let result = {
                    cancelled: false,
                    message: null,
                };
                switch (err[0]) {
                    case null:
                    case 'USER_CANCELLED':
                        result.cancelled = true;
                        result.message = 'Scan was cancelled.';
                        break;
                    case 'SCANNER_OPEN':
                        result.message = 'Another scan is already in progress.';
                        break;
                    default:
                        result.message = e[0] || 'Unknown error.';
                        break;
                }
                onError(result);
            },
            'cordova-plugin-barcode-scanner',
            'startScan',
            [ config ]
        );
    }
}

const barcodeScanner = new BarcodeScanner();
module.exports = barcodeScanner;
