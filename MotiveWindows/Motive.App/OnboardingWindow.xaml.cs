using System;
using System.Windows;
using System.Windows.Media;
using Motive.Core;

namespace Motive.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class OnboardingWindow : Wpf.Ui.Controls.FluentWindow
    {
        private readonly CredentialStore _credentialStore;
        public bool IsOnboardingSuccess { get; private set; }

        public OnboardingWindow()
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
            IsOnboardingSuccess = false;
        }

        private void PasswordBox_PasswordChanged(object sender, RoutedEventArgs e)
        {
            var hasOpenAi = !string.IsNullOrWhiteSpace(OpenAiPasswordBox.Password);
            var hasAnthropic = !string.IsNullOrWhiteSpace(AnthropicPasswordBox.Password);

            if (hasOpenAi || hasAnthropic)
            {
                StartButton.IsEnabled = true;
                WarningTextBlock.Text = "Credentials entered. Click Start Motive to proceed.";
                WarningTextBlock.Foreground = new SolidColorBrush(Color.FromRgb(16, 185, 129)); // Green #10B981
            }
            else
            {
                StartButton.IsEnabled = false;
                WarningTextBlock.Text = "* Paste at least one API key to proceed.";
                WarningTextBlock.Foreground = new SolidColorBrush(Color.FromRgb(239, 68, 68)); // Red #EF4444
            }
        }

        private void StartButton_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                var openAiKey = OpenAiPasswordBox.Password.Trim();
                var anthropicKey = AnthropicPasswordBox.Password.Trim();

                // Save keys securely in DPAPI CredentialStore
                if (!string.IsNullOrEmpty(openAiKey))
                {
                    _credentialStore.Write("OpenAiApiKey", openAiKey);
                }
                if (!string.IsNullOrEmpty(anthropicKey))
                {
                    _credentialStore.Write("AnthropicApiKey", anthropicKey);
                }

                IsOnboardingSuccess = true;
                this.Close();
            }
            catch (Exception ex)
            {
                MessageBox.Show($"Failed to save API keys securely: {ex.Message}", "Security Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void QuitButton_Click(object sender, RoutedEventArgs e)
        {
            IsOnboardingSuccess = false;
            this.Close();
        }
    }
}
