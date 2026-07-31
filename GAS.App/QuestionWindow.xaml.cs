using System;
using System.Collections.Generic;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

namespace GAS.App
{
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public partial class QuestionWindow : Wpf.Ui.Controls.FluentWindow
    {
        public string RequestId { get; }
        public string[][] SelectedAnswers { get; private set; } = Array.Empty<string[]>();
        public bool WasCancelled { get; private set; } = true;

        private readonly List<UIElement> _inputControls = new();

        /// <summary>
        /// Creates a native question dialog.
        /// </summary>
        /// <param name="requestId">Question request ID from SSE event.</param>
        /// <param name="questionText">The question header text.</param>
        /// <param name="options">List of option strings (if any).</param>
        /// <param name="isMultiSelect">True if multiple checkboxes are allowed; false for radio buttons.</param>
        /// <param name="allowCustomInput">True if a free-text input box should be provided.</param>
        public QuestionWindow(
            string requestId,
            string questionText,
            List<string>? options = null,
            bool isMultiSelect = false,
            bool allowCustomInput = true)
        {
            InitializeComponent();

            try
            {
                Wpf.Ui.Controls.WindowBackdrop.ApplyBackdrop(this, Wpf.Ui.Controls.WindowBackdropType.Mica);
            }
            catch
            {
                // Fallback to XAML background
            }

            RequestId = requestId;
            QuestionTitleBlock.Text = string.IsNullOrEmpty(questionText) ? "Agent Question" : questionText;

            BuildOptionsUI(options ?? new List<string>(), isMultiSelect, allowCustomInput);
        }

        private void BuildOptionsUI(List<string> options, bool isMultiSelect, bool allowCustomInput)
        {
            OptionsStackPanel.Children.Clear();
            _inputControls.Clear();

            if (options.Count > 0)
            {
                if (isMultiSelect)
                {
                    foreach (var option in options)
                    {
                        var cb = new CheckBox
                        {
                            Content = option,
                            Foreground = new SolidColorBrush(Color.FromRgb(241, 245, 249)),
                            FontSize = 13,
                            Margin = new Thickness(0, 4, 0, 8)
                        };
                        OptionsStackPanel.Children.Add(cb);
                        _inputControls.Add(cb);
                    }
                }
                else
                {
                    var isFirst = true;
                    foreach (var option in options)
                    {
                        var rb = new RadioButton
                        {
                            Content = option,
                            GroupName = "QuestionOptionsGroup",
                            IsChecked = isFirst,
                            Foreground = new SolidColorBrush(Color.FromRgb(241, 245, 249)),
                            FontSize = 13,
                            Margin = new Thickness(0, 4, 0, 8)
                        };
                        OptionsStackPanel.Children.Add(rb);
                        _inputControls.Add(rb);
                        isFirst = false;
                    }
                }
            }

            if (allowCustomInput || options.Count == 0)
            {
                var label = new TextBlock
                {
                    Text = options.Count > 0 ? "Or type a custom answer:" : "Your response:",
                    FontSize = 12,
                    Foreground = new SolidColorBrush(Color.FromRgb(148, 163, 184)),
                    Margin = new Thickness(0, 10, 0, 6)
                };
                OptionsStackPanel.Children.Add(label);

                var tb = new TextBox
                {
                    FontFamily = new FontFamily("Segoe UI Variable Text"),
                    FontSize = 13,
                    Foreground = new SolidColorBrush(Color.FromRgb(241, 245, 249)),
                    Background = new SolidColorBrush(Color.FromRgb(24, 24, 29)),
                    BorderBrush = new SolidColorBrush(Color.FromRgb(42, 42, 52)),
                    BorderThickness = new Thickness(1),
                    Padding = new Thickness(10, 8, 10, 8),
                    TextWrapping = TextWrapping.Wrap,
                    AcceptsReturn = true,
                    MinHeight = 60
                };
                OptionsStackPanel.Children.Add(tb);
                _inputControls.Add(tb);
            }
        }

        private void SubmitButton_Click(object sender, RoutedEventArgs e)
        {
            var selectedList = new List<string>();

            foreach (var control in _inputControls)
            {
                if (control is RadioButton { IsChecked: true } rb && rb.Content is string rbText)
                {
                    selectedList.Add(rbText);
                }
                else if (control is CheckBox { IsChecked: true } cb && cb.Content is string cbText)
                {
                    selectedList.Add(cbText);
                }
                else if (control is TextBox tb && !string.IsNullOrWhiteSpace(tb.Text))
                {
                    selectedList.Add(tb.Text.Trim());
                }
            }

            if (selectedList.Count == 0)
            {
                selectedList.Add("No answer provided");
            }

            SelectedAnswers = new[] { selectedList.ToArray() };
            WasCancelled = false;
            DialogResult = true;
            Close();
        }

        private void CancelButton_Click(object sender, RoutedEventArgs e)
        {
            WasCancelled = true;
            DialogResult = false;
            Close();
        }
    }
}
