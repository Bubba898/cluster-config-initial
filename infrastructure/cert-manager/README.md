# HTTPS/TLS Setup with cert-manager

This directory contains the configuration for automatic TLS certificate management using cert-manager with a self-signed Certificate Authority (CA).

## What's Included

1. **cert-manager** - Kubernetes certificate manager
2. **Self-signed ClusterIssuer** - Bootstrap issuer for creating the root CA
3. **Homelab Root CA** - Your own Certificate Authority for issuing certificates
4. **Wildcard Certificate** - Automatically generated certificate for `*.${INGRESS_IP}.sslip.io`

## How It Works

1. cert-manager creates a self-signed root CA certificate (`homelab-ca`)
2. The CA issuer (`homelab-ca-issuer`) uses this root CA to sign certificates
3. A wildcard certificate is automatically generated and renewed for all your services
4. Istio Gateway uses this certificate to provide HTTPS for all services

## Deployment

The cert-manager setup will be automatically deployed via Flux when you commit and push these changes.

### Manual Application (if needed)

```bash
# Apply cert-manager and related resources
kubectl apply -k infrastructure/cert-manager

# Wait for cert-manager to be ready
kubectl wait --for=condition=Available --timeout=300s \
  deployment/cert-manager -n cert-manager

# Check certificate status
kubectl get certificate -A
kubectl describe certificate wildcard-sslip-cert -n istio-system
```

## Trust the CA Certificate on Your Devices

To avoid browser warnings, you need to trust the root CA certificate on your local devices.

### Step 1: Extract the CA Certificate

```bash
# Extract the CA certificate
kubectl get secret homelab-ca-secret -n cert-manager \
  -o jsonpath='{.data.tls\.crt}' | base64 -d > homelab-ca.crt

# View the certificate (optional)
openssl x509 -in homelab-ca.crt -text -noout
```

### Step 2: Trust the Certificate

#### macOS
```bash
# Import to keychain
sudo security add-trusted-cert -d -r trustRoot \
  -k /Library/Keychains/System.keychain homelab-ca.crt

# Or use Keychain Access GUI:
# 1. Open "Keychain Access" application
# 2. Drag homelab-ca.crt into "System" keychain
# 3. Double-click the certificate
# 4. Expand "Trust" section
# 5. Set "When using this certificate" to "Always Trust"
```

#### Linux (Ubuntu/Debian)
```bash
# Copy to trusted certificates directory
sudo cp homelab-ca.crt /usr/local/share/ca-certificates/homelab-ca.crt

# Update CA certificates
sudo update-ca-certificates

# For Firefox (uses its own certificate store)
# Import manually via Preferences → Privacy & Security → Certificates → View Certificates
```

#### Windows
```bash
# Import the certificate
certutil -addstore -f "ROOT" homelab-ca.crt

# Or use GUI:
# 1. Double-click homelab-ca.crt
# 2. Click "Install Certificate"
# 3. Choose "Local Machine"
# 4. Select "Place all certificates in the following store"
# 5. Browse to "Trusted Root Certification Authorities"
# 6. Click "Next" and "Finish"
```

#### iOS/iPadOS
```bash
# Transfer homelab-ca.crt to your device via AirDrop or email
# 1. Tap the certificate file
# 2. Go to Settings → General → VPN & Device Management
# 3. Tap the profile and install it
# 4. Go to Settings → General → About → Certificate Trust Settings
# 5. Enable full trust for the certificate
```

#### Android
```bash
# Transfer homelab-ca.crt to your device
# 1. Go to Settings → Security → Encryption & credentials
# 2. Tap "Install a certificate" → "CA certificate"
# 3. Select the homelab-ca.crt file
# 4. Name it "Homelab CA" and tap OK
```

## Verification

After trusting the CA certificate and applying the changes:

```bash
# Check that the wildcard certificate is ready
kubectl get certificate wildcard-sslip-cert -n istio-system

# Should show:
# NAME                   READY   SECRET                AGE
# wildcard-sslip-cert    True    wildcard-sslip-tls    1m

# Check the secret exists
kubectl get secret wildcard-sslip-tls -n istio-system
```

Then visit your services:
- https://gitlab.${INGRESS_IP}.sslip.io
- https://headlamp.${INGRESS_IP}.sslip.io
- https://grafana.${INGRESS_IP}.sslip.io

You should see a valid HTTPS connection without warnings! 🎉

## Troubleshooting

### Certificate not ready

```bash
# Check certificate status
kubectl describe certificate wildcard-sslip-cert -n istio-system

# Check cert-manager logs
kubectl logs -n cert-manager deployment/cert-manager

# Check certificate request
kubectl get certificaterequest -n istio-system
kubectl describe certificaterequest -n istio-system
```

### Browser still shows warnings

1. Make sure you've installed the CA certificate correctly
2. Restart your browser after installing the CA certificate
3. Clear browser cache and SSL state
4. Check the certificate being served matches your CA:
   ```bash
   openssl s_client -connect gitlab.${INGRESS_IP}.sslip.io:443 -showcerts
   ```

### GitLab runner TLS issues

The GitLab runner configuration includes `tls_verify = false` for self-signed certificates. If you want to enable verification:

1. Copy the CA certificate into the runner pods
2. Update the runner configuration to point to the CA certificate
3. Remove the `tls_verify = false` line

## Certificate Renewal

Certificates are automatically renewed by cert-manager:
- Wildcard certificate: 90 days validity, renewed 30 days before expiration
- Root CA: 10 years validity, renewed 1 year before expiration

No manual intervention required! 🚀

