package dev.rehan.passthrough.session;

import java.nio.charset.StandardCharsets;
import java.security.*;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;
import java.util.HexFormat;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/** JDK Ed25519 only: guests never receive the authority signing key. */
public final class SessionCrypto {
    private static final SecureRandom RANDOM = new SecureRandom();
    public static String encode(byte[] data) { return Base64.getUrlEncoder().withoutPadding().encodeToString(data); }
    public static byte[] decode(String data) { return Base64.getUrlDecoder().decode(data); }
    public static String nonce() { byte[] b = new byte[32]; RANDOM.nextBytes(b); return encode(b); }
    public static String sha256(String text) {
        try { return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256").digest(text.getBytes(StandardCharsets.UTF_8))); }
        catch (GeneralSecurityException e) { throw new IllegalStateException(e); }
    }
    public static KeyPair keys() {
        try { return KeyPairGenerator.getInstance("Ed25519").generateKeyPair(); }
        catch (GeneralSecurityException e) { throw new IllegalStateException(e); }
    }
    public static PublicKey publicKey(String encoded) {
        try { return KeyFactory.getInstance("Ed25519").generatePublic(new X509EncodedKeySpec(decode(encoded))); }
        catch (GeneralSecurityException | IllegalArgumentException e) { throw new IllegalArgumentException("Invalid public key", e); }
    }
    public static PrivateKey privateKey(String encoded) {
        try { return KeyFactory.getInstance("Ed25519").generatePrivate(new PKCS8EncodedKeySpec(decode(encoded))); }
        catch (GeneralSecurityException | IllegalArgumentException e) { throw new IllegalArgumentException("Invalid private key", e); }
    }
    public static String sign(PrivateKey key, String text) {
        try {
            Signature s = Signature.getInstance("Ed25519"); s.initSign(key);
            s.update(text.getBytes(StandardCharsets.UTF_8)); return encode(s.sign());
        } catch (GeneralSecurityException e) { throw new IllegalStateException(e); }
    }
    public static String hmac(String secret, String text) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256"); mac.init(new SecretKeySpec(decode(secret), "HmacSHA256"));
            return encode(mac.doFinal(text.getBytes(StandardCharsets.UTF_8)));
        } catch (GeneralSecurityException e) { throw new IllegalStateException(e); }
    }
    public static boolean verifyHmac(String secret, String text, String proof) {
        try { return MessageDigest.isEqual(decode(hmac(secret, text)), decode(proof)); }
        catch (IllegalArgumentException e) { return false; }
    }
    public static boolean verify(PublicKey key, String text, String proof) {
        try {
            Signature s = Signature.getInstance("Ed25519"); s.initVerify(key);
            s.update(text.getBytes(StandardCharsets.UTF_8)); return s.verify(decode(proof));
        } catch (GeneralSecurityException | IllegalArgumentException e) { return false; }
    }
    private SessionCrypto() {}
}
