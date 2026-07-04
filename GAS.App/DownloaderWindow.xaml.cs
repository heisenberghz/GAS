using System;
using System.Threading.Tasks;
using System.Windows;
using GAS.Core;

namespace GAS.App
{
    public partial class DownloaderWindow : Wpf.Ui.Controls.FluentWindow
    {
        private readonly EngineDownloader _downloader;
        private bool _isDownloading = false;
        private bool _hasFailed = false;

        public bool IsDownloadSuccess { get; private set; } = false;

        public DownloaderWindow()
        {
            InitializeComponent();
            _downloader = new EngineDownloader();
            _downloader.ProgressChanged += OnProgressChanged;
            _downloader.StatusChanged += OnStatusChanged;
            
            Loaded += DownloaderWindow_Loaded;
        }

        private async void DownloaderWindow_Loaded(object sender, RoutedEventArgs e)
        {
            await StartDownload();
        }

        private async Task StartDownload()
        {
            if (_isDownloading) return;

            _isDownloading = true;
            _hasFailed = false;
            IsDownloadSuccess = false;
            ErrorTextBlock.Text = "";
            ActionButton.Content = "Cancel";
            ActionButton.Appearance = Wpf.Ui.Controls.ControlAppearance.Secondary;

            try
            {
                await _downloader.DownloadAsync();
                IsDownloadSuccess = true;
                DialogResult = true;
                Close();
            }
            catch (Exception ex)
            {
                _hasFailed = true;
                _isDownloading = false;
                ErrorTextBlock.Text = ex.Message;
                StatusTextBlock.Text = "Setup failed.";
                ActionButton.Content = "Retry";
                ActionButton.Appearance = Wpf.Ui.Controls.ControlAppearance.Primary;
            }
        }

        private void OnProgressChanged(double progress)
        {
            Dispatcher.Invoke(() =>
            {
                DownloadProgressBar.Value = progress;
            });
        }

        private void OnStatusChanged(string status)
        {
            Dispatcher.Invoke(() =>
            {
                StatusTextBlock.Text = status;
            });
        }

        private async void ActionButton_Click(object sender, RoutedEventArgs e)
        {
            if (_hasFailed)
            {
                // If it failed, action button acts as a retry
                await StartDownload();
            }
            else
            {
                // Otherwise, cancel/close
                DialogResult = false;
                Close();
            }
        }
    }
}
