// ===== crypto.rs: 加密/哈希模块 =====
//
// 提供 MD5/SHA256/AES-CBC/Base64/HMAC-SHA256
// 对应 Legado 的 java.aesEncode/java.md5Encode/CryptoJS 等 API
//
// 添加新的加密函数：
//   1. 写一个 pub fn，标注 #[napi]
//   2. 在 Cargo.toml 添加需要的 crate 依赖
//   3. 在 index.js 的 crypto 分组中添加 JS 降级实现

use napi::bindgen_prelude::*;
use napi_derive::napi;

// ----- 哈希 -----

/// MD5 哈希（32 位小写 hex）
#[napi]
pub fn md5(input: String) -> String {
    use md5::{Digest, Md5};
    let mut hasher = Md5::new();
    hasher.update(input.as_bytes());
    hex::encode(hasher.finalize())
}

/// SHA256 哈希（64 位小写 hex）
#[napi]
pub fn sha256(input: String) -> String {
    use sha2::{Digest, Sha256};
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    hex::encode(hasher.finalize())
}

// ----- 编解码 -----

/// Base64 编码
#[napi]
pub fn base64_encode(input: String) -> String {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    STANDARD.encode(input.as_bytes())
}

/// Base64 解码
#[napi]
pub fn base64_decode(input: String) -> Result<String> {
    use base64::engine::general_purpose::STANDARD;
    use base64::Engine;
    let decoded = STANDARD
        .decode(&input)
        .map_err(|e| Error::from_reason(format!("Base64 decode error: {}", e)))?;
    String::from_utf8(decoded)
        .map_err(|e| Error::from_reason(format!("UTF-8 decode error: {}", e)))
}

// ----- 对称加密 -----

/// AES-CBC 加密（256-bit key, PKCS7 padding）
///
/// @param data 明文
/// @param key  32 字节密钥的 hex 字符串（64 字符）
/// @param iv   16 字节 IV 的 hex 字符串（32 字符）
/// @returns Base64 编码的密文
#[napi]
pub fn aes_cbc_encrypt(data: String, key: String, iv: String) -> Result<String> {
    use aes::Aes256;
    use cbc::cipher::{BlockEncryptMut, KeyIvInit};
    use cbc::Encryptor;
    type Aes256CbcEnc = Encryptor<Aes256>;

    let key_bytes = hex::decode(&key)
        .map_err(|e| Error::from_reason(format!("Invalid key hex: {}", e)))?;
    let iv_bytes = hex::decode(&iv)
        .map_err(|e| Error::from_reason(format!("Invalid iv hex: {}", e)))?;

    if key_bytes.len() != 32 {
        return Err(Error::from_reason("Key must be 32 bytes (256-bit) hex"));
    }
    if iv_bytes.len() != 16 {
        return Err(Error::from_reason("IV must be 16 bytes hex"));
    }

    let encryptor = Aes256CbcEnc::new_from_slices(&key_bytes, &iv_bytes)
        .map_err(|e| Error::from_reason(format!("AES init error: {}", e)))?;

    let data_bytes = data.as_bytes();
    let mut buf = vec![0u8; data_bytes.len() + 16];
    buf[..data_bytes.len()].copy_from_slice(data_bytes);

    let encrypted = encryptor
        .encrypt_padded_mut::<cbc::cipher::block_padding::Pkcs7>(&mut buf, data_bytes.len())
        .map_err(|e| Error::from_reason(format!("AES encrypt error: {}", e)))?;

    Ok(base64::engine::general_purpose::STANDARD.encode(encrypted))
}

/// AES-CBC 解密（256-bit key, PKCS7 padding）
///
/// @param data Base64 编码的密文
/// @param key  32 字节密钥的 hex 字符串（64 字符）
/// @param iv   16 字节 IV 的 hex 字符串（32 字符）
/// @returns 明文字符串
#[napi]
pub fn aes_cbc_decrypt(data: String, key: String, iv: String) -> Result<String> {
    use aes::Aes256;
    use cbc::cipher::{BlockDecryptMut, KeyIvInit};
    use cbc::Decryptor;
    type Aes256CbcDec = Decryptor<Aes256>;

    let key_bytes = hex::decode(&key)
        .map_err(|e| Error::from_reason(format!("Invalid key hex: {}", e)))?;
    let iv_bytes = hex::decode(&iv)
        .map_err(|e| Error::from_reason(format!("Invalid iv hex: {}", e)))?;

    let ciphertext = base64::engine::general_purpose::STANDARD
        .decode(&data)
        .map_err(|e| Error::from_reason(format!("Base64 decode error: {}", e)))?;

    let decryptor = Aes256CbcDec::new_from_slices(&key_bytes, &iv_bytes)
        .map_err(|e| Error::from_reason(format!("AES init error: {}", e)))?;

    let mut buf = ciphertext;
    let decrypted = decryptor
        .decrypt_padded_mut::<cbc::cipher::block_padding::Pkcs7>(&mut buf)
        .map_err(|e| Error::from_reason(format!("AES decrypt error: {}", e)))?;

    String::from_utf8(decrypted.to_vec())
        .map_err(|e| Error::from_reason(format!("UTF-8 decode error: {}", e)))
}

// ----- 签名 -----

/// HMAC-SHA256 签名
///
/// @param key     签名密钥
/// @param message 待签名消息
/// @returns 小写 hex 字符串
#[napi]
pub fn hmac_sha256(key: String, message: String) -> String {
    use hmac::{Hmac, Mac};
    use sha2::Sha256;
    type HmacSha256 = Hmac<Sha256>;

    let mut mac = HmacSha256::new_from_slice(key.as_bytes())
        .expect("HMAC can take key of any size");
    mac.update(message.as_bytes());
    hex::encode(mac.finalize().into_bytes())
}
