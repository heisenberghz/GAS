using System;
using System.Collections.Generic;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Runtime.Versioning;

namespace GAS.Core
{
    [SupportedOSPlatform("windows")]
    public class CredentialStore
    {
        private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("GASSecretEntropySalt");
        private readonly string _storeFilePath;
        private readonly object _lock = new object();

        public CredentialStore()
        {
            _storeFilePath = Path.Combine(BinaryManager.AppSupportDirectory, "secrets.dat");
        }

        public CredentialStore(string customPath)
        {
            _storeFilePath = customPath;
        }

        /// <summary>
        /// Reads a credential value by key.
        /// </summary>
        public string? Read(string key)
        {
            if (string.IsNullOrEmpty(key)) return null;

            lock (_lock)
            {
                var secrets = LoadSecrets();
                return secrets.TryGetValue(key, out var value) ? value : null;
            }
        }

        /// <summary>
        /// Writes a credential value.
        /// </summary>
        public void Write(string key, string value)
        {
            if (string.IsNullOrEmpty(key)) return;

            lock (_lock)
            {
                var secrets = LoadSecrets();
                secrets[key] = value;
                SaveSecrets(secrets);
            }
        }

        /// <summary>
        /// Deletes a credential value.
        /// </summary>
        public void Delete(string key)
        {
            if (string.IsNullOrEmpty(key)) return;

            lock (_lock)
            {
                var secrets = LoadSecrets();
                if (secrets.Remove(key))
                {
                    SaveSecrets(secrets);
                }
            }
        }

        /// <summary>
        /// Deletes all credentials stored.
        /// </summary>
        public void DeleteAll()
        {
            lock (_lock)
            {
                try
                {
                    if (File.Exists(_storeFilePath))
                    {
                        File.Delete(_storeFilePath);
                    }
                }
                catch (Exception ex)
                {
                    throw new InvalidOperationException("Failed to delete the credential store file.", ex);
                }
            }
        }

        private Dictionary<string, string> LoadSecrets()
        {
            if (!File.Exists(_storeFilePath))
            {
                return new Dictionary<string, string>();
            }

            try
            {
                byte[] encryptedBytes = File.ReadAllBytes(_storeFilePath);
                if (encryptedBytes.Length == 0)
                {
                    return new Dictionary<string, string>();
                }

                // Decrypt using DPAPI
                byte[] decryptedBytes = ProtectedData.Unprotect(
                    encryptedBytes, 
                    Entropy, 
                    DataProtectionScope.CurrentUser
                );

                string json = Encoding.UTF8.GetString(decryptedBytes);
                return JsonSerializer.Deserialize<Dictionary<string, string>>(json) ?? new Dictionary<string, string>();
            }
            catch (CryptographicException)
            {
                // Decryption failed (e.g., store is corrupted or user environment changed)
                return new Dictionary<string, string>();
            }
            catch (Exception)
            {
                return new Dictionary<string, string>();
            }
        }

        private void SaveSecrets(Dictionary<string, string> secrets)
        {
            try
            {
                var dir = Path.GetDirectoryName(_storeFilePath);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                string json = JsonSerializer.Serialize(secrets);
                byte[] decryptedBytes = Encoding.UTF8.GetBytes(json);

                // Encrypt using DPAPI
                byte[] encryptedBytes = ProtectedData.Protect(
                    decryptedBytes, 
                    Entropy, 
                    DataProtectionScope.CurrentUser
                );

                File.WriteAllBytes(_storeFilePath, encryptedBytes);
            }
            catch (Exception ex)
            {
                throw new InvalidOperationException("Failed to save credentials securely.", ex);
            }
        }
    }
}

