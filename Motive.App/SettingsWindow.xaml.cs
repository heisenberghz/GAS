using System;
using System.Diagnostics;
using System.IO;
using System.Windows;
using System.Windows.Controls;
using Microsoft.Win32;
using Motive.Core;

namespace Motive.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class SettingsWindow : Wpf.Ui.Controls.FluentWindow
    {
        private readonly CredentialStore _credentialStore;

        public SettingsWindow()
        {
            InitializeComponent();

            try
            {
                Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica);
            }
            catch
            {
                // Fallback to custom brush in XAML
            }

            _credentialStore = new CredentialStore();
            LoadCurrentSettings();
        }

        private void LoadCurrentSettings()
        {
            try
            {
                // 1. Load General Settings
                var settings = SettingsManager.Load();

                StartOnBootCheckBox.IsChecked = settings.StartOnBoot;
                EnginePathTextBox.Text = settings.CustomBinaryPath;

                // 2. Load API Keys
                OpenAiPasswordBox.Password = _credentialStore.Read("OpenAiApiKey") ?? string.Empty;
                AnthropicPasswordBox.Password = _credentialStore.Read("AnthropicApiKey") ?? string.Empty;

                // 3. Load Hotkey selections
                CtrlCheckBox.IsChecked = settings.CtrlModifier;
                ShiftCheckBox.IsChecked = settings.ShiftModifier;
                AltCheckBox.IsChecked = settings.AltModifier;

                // Map Hotkey Key select item
                bool foundKey = false;
                foreach (ComboBoxItem item in KeyComboBox.Items)
                {
                    if (item.Content.ToString() == settings.HotkeyKey)
                    {
                        KeyComboBox.SelectedItem = item;
                        foundKey = true;
                        break;
                    }
                }
                if (!foundKey && KeyComboBox.Items.Count > 0)
                {
                    KeyComboBox.SelectedIndex = 0; // Default to Space
                }
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to load settings: {ex.Message}", "Settings Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void BrowseButton_Click(object sender, RoutedEventArgs e)
        {
            var openFileDialog = new OpenFileDialog
            {
                Title = "Select OpenCode Engine CLI",
                Filter = "Executables and Scripts (*.exe;*.cmd)|*.exe;*.cmd|All files (*.*)|*.*"
            };

            if (openFileDialog.ShowDialog() == true)
            {
                EnginePathTextBox.Text = openFileDialog.FileName;
            }
        }

        private void SaveButton_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                // 1. Read values from inputs
                var settings = new AppSettings
                {
                    StartOnBoot = StartOnBootCheckBox.IsChecked ?? false,
                    CustomBinaryPath = EnginePathTextBox.Text.Trim(),
                    CtrlModifier = CtrlCheckBox.IsChecked ?? false,
                    ShiftModifier = ShiftCheckBox.IsChecked ?? false,
                    AltModifier = AltCheckBox.IsChecked ?? false,
                    HotkeyKey = ((ComboBoxItem)KeyComboBox.SelectedItem)?.Content?.ToString() ?? "Space"
                };

                // 2. Save encrypted API keys
                _credentialStore.Write("OpenAiApiKey", OpenAiPasswordBox.Password.Trim());
                _credentialStore.Write("AnthropicApiKey", AnthropicPasswordBox.Password.Trim());

                // 3. Save JSON Settings
                SettingsManager.Save(settings);

                // 4. Update Windows startup Registry key
                UpdateStartupRegistry(settings.StartOnBoot);

                // 5. Rebind global hotkey hook in App
                if (Application.Current is App app)
                {
                    app.RebindHotkey(settings);
                }

                this.Close();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to save settings: {ex.Message}", "Settings Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e)
        {
            this.Close();
        }

        private void UpdateStartupRegistry(bool startOnBoot)
        {
            try
            {
                const string runKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
                using (var key = Registry.CurrentUser.OpenSubKey(runKey, true))
                {
                    if (key != null)
                    {
                        if (startOnBoot)
                        {
                            var currentExe = Process.GetCurrentProcess().MainModule?.FileName;
                            if (!string.IsNullOrEmpty(currentExe))
                            {
                                key.SetValue("Motive", $"\"{currentExe}\"");
                            }
                        }
                        else
                        {
                            key.DeleteValue("Motive", false);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to update startup registry value: {ex.Message}");
            }
        }
    }
}
