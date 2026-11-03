# ActionTracker.ps1
# A lightweight, always-on-desktop action tracker widget for Windows.
# No installation, no admin rights: uses only Windows PowerShell + built-in .NET (WPF).
# Data is stored per-user under %APPDATA%\ActionTracker\state.json.
#
# Features:
#   - Assign each action to a PROJECT (type a new name or pick an existing one).
#     Each action shows a colour-coded project tag on its left.
#   - Optional due date per action (date column); overdue active items are flagged.
#   - Check off an action -> it moves to the "Completed" view, stored for review,
#     with its checkbox replaced by a "done on <date>" stamp.
#   - Click that date stamp to UNDO completion (reopens the action as active).

$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# --- Task model with change notification ---
Add-Type @"
using System;
using System.ComponentModel;
public class TrackerTask : INotifyPropertyChanged {
    private string _text;
    private string _project = "";
    private bool _done;
    private DateTime? _due;
    private DateTime? _completedAt;
    public event PropertyChangedEventHandler PropertyChanged;

    public string Text {
        get { return _text; }
        set { _text = value; OnChanged("Text"); }
    }
    public string Project {
        get { return _project; }
        set { _project = (value == null ? "" : value); OnChanged("Project"); OnChanged("ProjectColor"); }
    }
    public DateTime? Due {
        get { return _due; }
        set { _due = value; OnChanged("Due"); OnChanged("IsOverdue"); }
    }
    public DateTime? CompletedAt {
        get { return _completedAt; }
        set { _completedAt = value; OnChanged("CompletedAt"); }
    }
    public bool Done {
        get { return _done; }
        set {
            if (_done != value) {
                _done = value;
                if (_done) { if (!_completedAt.HasValue) CompletedAt = DateTime.Now; }
                else { CompletedAt = null; }
                OnChanged("Done");
                OnChanged("IsOverdue");
            }
        }
    }
    public bool IsOverdue {
        get { return _due.HasValue && !_done && _due.Value.Date < DateTime.Now.Date; }
    }
    // A stable colour (hex string) derived from the project name, for the tag.
    public string ProjectColor {
        get {
            if (string.IsNullOrEmpty(_project)) return "#00000000";
            string[] pal = { "#3B6EA5","#6E8B3D","#A5673B","#7D5BA6","#2F8F83","#A53B5A","#8A6D1E","#4A6B8A" };
            int h = 0;
            foreach (char c in _project) { h = h * 31 + c; }
            int idx = ((h % pal.Length) + pal.Length) % pal.Length;
            return pal[idx];
        }
    }
    private void OnChanged(string name) {
        PropertyChangedEventHandler h = PropertyChanged;
        if (h != null) h(this, new PropertyChangedEventArgs(name));
    }
}
"@

# --- Storage paths ---
$AppDir    = Join-Path $env:APPDATA 'ActionTracker'
$StateFile = Join-Path $AppDir 'state.json'
if (-not (Test-Path $AppDir)) { New-Item -ItemType Directory -Path $AppDir -Force | Out-Null }

# --- UI definition ---
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        x:Name="Win"
        Title="Action Tracker"
        Width="430" Height="470"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        ShowInTaskbar="True" Topmost="False" ResizeMode="CanResizeWithGrip"
        MinWidth="340" MinHeight="240"
        FontFamily="Segoe UI">
  <Window.Resources>
    <Style x:Key="IconBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Foreground" Value="#9AA0A6"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="13"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="5" Padding="4,1">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#33FFFFFF"/>
          <Setter Property="Foreground" Value="#FFFFFF"/>
        </Trigger>
      </Style.Triggers>
    </Style>

    <Style x:Key="StampBtn" TargetType="Button">
      <Setter Property="Background" Value="Transparent"/>
      <Setter Property="BorderThickness" Value="0"/>
      <Setter Property="Foreground" Value="#8BD5A0"/>
      <Setter Property="Cursor" Value="Hand"/>
      <Setter Property="FontSize" Value="11"/>
      <Setter Property="Padding" Value="0,0,8,0"/>
      <Setter Property="HorizontalContentAlignment" Value="Left"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Background="{TemplateBinding Background}" CornerRadius="5" Padding="4,1">
              <ContentPresenter VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True">
          <Setter Property="Background" Value="#33FFFFFF"/>
          <Setter Property="Foreground" Value="#B8ECC6"/>
        </Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Border CornerRadius="12" Background="#E61F2023" BorderBrush="#33FFFFFF" BorderThickness="1">
    <Grid Margin="2">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="*"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Header (drag handle) -->
      <Grid x:Name="Header" Grid.Row="0" Background="Transparent" Margin="10,8,8,4">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock Grid.Column="0" Text="Action Tracker" Foreground="#E8EAED"
                   FontWeight="SemiBold" FontSize="13" VerticalAlignment="Center"/>
        <Button x:Name="ViewBtn" Grid.Column="1" Style="{StaticResource IconBtn}"
                Content="Active" FontSize="11" ToolTip="Switch between active and completed"/>
        <Button x:Name="PinBtn" Grid.Column="2" Style="{StaticResource IconBtn}"
                Content="Top" ToolTip="Toggle always-on-top"/>
        <Button x:Name="CloseBtn" Grid.Column="3" Style="{StaticResource IconBtn}"
                Content="&#x2715;" ToolTip="Close"/>
      </Grid>

      <!-- Add row: project + task text + optional due date -->
      <Grid x:Name="AddRow" Grid.Row="1" Margin="10,2,10,6">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <ComboBox x:Name="ProjInput" Grid.Column="0" Width="104" IsEditable="True"
                  VerticalAlignment="Center" FontSize="12" Margin="0,0,6,0"
                  ToolTip="Project: type a new name or pick an existing one"/>
        <Border Grid.Column="1" Background="#2A2C2F" CornerRadius="8" Margin="0,0,6,0">
          <TextBox x:Name="Input" Background="Transparent" BorderThickness="0"
                   Foreground="#F1F3F4" CaretBrush="#F1F3F4" FontSize="13"
                   Padding="8,6" VerticalContentAlignment="Center"
                   ToolTip="Type an action and press Enter"/>
        </Border>
        <DatePicker x:Name="DueInput" Grid.Column="2" Width="116" VerticalAlignment="Center"
                    FontSize="11" ToolTip="Optional due date for the new action"/>
      </Grid>

      <!-- Task list -->
      <ListBox x:Name="List" Grid.Row="2" Background="Transparent" BorderThickness="0"
               Margin="4,0,4,0" ScrollViewer.HorizontalScrollBarVisibility="Disabled"
               HorizontalContentAlignment="Stretch">
        <ListBox.ItemContainerStyle>
          <Style TargetType="ListBoxItem">
            <Setter Property="Background" Value="Transparent"/>
            <Setter Property="Padding" Value="0"/>
            <Setter Property="HorizontalContentAlignment" Value="Stretch"/>
            <Setter Property="Template">
              <Setter.Value>
                <ControlTemplate TargetType="ListBoxItem">
                  <Border Background="{TemplateBinding Background}" CornerRadius="6" Padding="6,3" Margin="4,1">
                    <ContentPresenter/>
                  </Border>
                </ControlTemplate>
              </Setter.Value>
            </Setter>
            <Style.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter Property="Background" Value="#22FFFFFF"/>
              </Trigger>
            </Style.Triggers>
          </Style>
        </ListBox.ItemContainerStyle>
        <ListBox.ItemTemplate>
          <DataTemplate>
            <Grid>
              <Grid.ColumnDefinitions>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="*"/>
                <ColumnDefinition Width="Auto"/>
                <ColumnDefinition Width="Auto"/>
              </Grid.ColumnDefinitions>

              <!-- Column 0: checkbox (active) OR completion stamp that reopens (completed) -->
              <Grid Grid.Column="0" VerticalAlignment="Center" Margin="0,0,6,0">
                <CheckBox IsChecked="{Binding Done, Mode=TwoWay}" VerticalAlignment="Center"
                          ToolTip="Mark complete">
                  <CheckBox.Style>
                    <Style TargetType="CheckBox">
                      <Setter Property="Visibility" Value="Visible"/>
                      <Style.Triggers>
                        <DataTrigger Binding="{Binding Done}" Value="True">
                          <Setter Property="Visibility" Value="Collapsed"/>
                        </DataTrigger>
                      </Style.Triggers>
                    </Style>
                  </CheckBox.Style>
                </CheckBox>
                <Button Tag="reopen"
                        Content="{Binding CompletedAt, StringFormat='&#x2713; {0:MMM d}'}"
                        ToolTip="Completed — click to undo / reopen">
                  <Button.Style>
                    <Style TargetType="Button" BasedOn="{StaticResource StampBtn}">
                      <Setter Property="Visibility" Value="Collapsed"/>
                      <Style.Triggers>
                        <DataTrigger Binding="{Binding Done}" Value="True">
                          <Setter Property="Visibility" Value="Visible"/>
                        </DataTrigger>
                      </Style.Triggers>
                    </Style>
                  </Button.Style>
                </Button>
              </Grid>

              <!-- Column 1: project tag -->
              <Border Grid.Column="1" CornerRadius="4" Padding="6,1" Margin="0,0,6,0"
                      VerticalAlignment="Center" Background="{Binding ProjectColor}">
                <Border.Style>
                  <Style TargetType="Border">
                    <Setter Property="Visibility" Value="Visible"/>
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding Project}" Value="">
                        <Setter Property="Visibility" Value="Collapsed"/>
                      </DataTrigger>
                    </Style.Triggers>
                  </Style>
                </Border.Style>
                <TextBlock Text="{Binding Project}" Foreground="#FFFFFF" FontSize="10"
                           FontWeight="SemiBold" MaxWidth="90" TextTrimming="CharacterEllipsis"
                           ToolTip="{Binding Project}"/>
              </Border>

              <!-- Column 2: action text -->
              <TextBlock Grid.Column="2" Text="{Binding Text}" TextWrapping="Wrap"
                         VerticalAlignment="Center" Foreground="#ECEFF1" FontSize="13">
                <TextBlock.Style>
                  <Style TargetType="TextBlock">
                    <Style.Triggers>
                      <DataTrigger Binding="{Binding Done}" Value="True">
                        <Setter Property="TextDecorations" Value="Strikethrough"/>
                        <Setter Property="Opacity" Value="0.5"/>
                      </DataTrigger>
                    </Style.Triggers>
                  </Style>
                </TextBlock.Style>
              </TextBlock>

              <!-- Column 3: due date (editable DatePicker when active, text when completed) -->
              <Grid Grid.Column="3" VerticalAlignment="Center" Margin="6,0,4,0">
                <StackPanel Orientation="Horizontal">
                  <TextBlock Text="!" Foreground="#FF7B72" FontWeight="Bold" FontSize="12"
                             VerticalAlignment="Center" Margin="0,0,3,0" ToolTip="Overdue">
                    <TextBlock.Style>
                      <Style TargetType="TextBlock">
                        <Setter Property="Visibility" Value="Collapsed"/>
                        <Style.Triggers>
                          <DataTrigger Binding="{Binding IsOverdue}" Value="True">
                            <Setter Property="Visibility" Value="Visible"/>
                          </DataTrigger>
                        </Style.Triggers>
                      </Style>
                    </TextBlock.Style>
                  </TextBlock>
                  <DatePicker SelectedDate="{Binding Due, Mode=TwoWay}" Width="116" FontSize="11">
                    <DatePicker.Style>
                      <Style TargetType="DatePicker">
                        <Setter Property="Visibility" Value="Visible"/>
                        <Style.Triggers>
                          <DataTrigger Binding="{Binding Done}" Value="True">
                            <Setter Property="Visibility" Value="Collapsed"/>
                          </DataTrigger>
                        </Style.Triggers>
                      </Style>
                    </DatePicker.Style>
                  </DatePicker>
                  <TextBlock Text="{Binding Due, StringFormat='due {0:MMM d}'}" Foreground="#9AA0A6"
                             FontSize="11" VerticalAlignment="Center">
                    <TextBlock.Style>
                      <Style TargetType="TextBlock">
                        <Setter Property="Visibility" Value="Collapsed"/>
                        <Style.Triggers>
                          <DataTrigger Binding="{Binding Done}" Value="True">
                            <Setter Property="Visibility" Value="Visible"/>
                          </DataTrigger>
                        </Style.Triggers>
                      </Style>
                    </TextBlock.Style>
                  </TextBlock>
                </StackPanel>
              </Grid>

              <!-- Column 4: delete -->
              <Button Grid.Column="4" Tag="del" Content="&#x2715;" Style="{StaticResource IconBtn}"
                      VerticalAlignment="Center" ToolTip="Delete"/>
            </Grid>
          </DataTemplate>
        </ListBox.ItemTemplate>
      </ListBox>

      <!-- Footer -->
      <Grid Grid.Row="3" Margin="12,4,12,10">
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <TextBlock x:Name="CountText" Grid.Column="0" Foreground="#9AA0A6" FontSize="11"
                   VerticalAlignment="Center"/>
        <Button x:Name="ClearBtn" Grid.Column="1" Style="{StaticResource IconBtn}"
                Content="Clear completed" FontSize="11" Visibility="Collapsed"
                ToolTip="Permanently remove all completed actions"/>
      </Grid>
    </Grid>
  </Border>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [System.Windows.Markup.XamlReader]::Load($reader)

# --- Grab named elements ---
$header    = $win.FindName('Header')
$inputBox  = $win.FindName('Input')
$projInput = $win.FindName('ProjInput')
$dueInput  = $win.FindName('DueInput')
$list      = $win.FindName('List')
$countText = $win.FindName('CountText')
$viewBtn   = $win.FindName('ViewBtn')
$pinBtn    = $win.FindName('PinBtn')
$closeBtn  = $win.FindName('CloseBtn')
$clearBtn  = $win.FindName('ClearBtn')

# --- State ---
$allTasks = New-Object 'System.Collections.ObjectModel.ObservableCollection[TrackerTask]'
$projects = New-Object 'System.Collections.ObjectModel.ObservableCollection[string]'
$list.ItemsSource     = $allTasks
$projInput.ItemsSource = $projects
$script:view = [System.Windows.Data.CollectionViewSource]::GetDefaultView($allTasks)
$script:showCompleted = $false
$script:suppressSave  = $true   # don't save while loading

# Filter: active view shows not-done; completed view shows done
$script:view.Filter = [Predicate[object]]{
    param($o)
    if ($script:showCompleted) { return [bool]$o.Done } else { return -not [bool]$o.Done }
}

function Add-Project([string]$name) {
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $name = $name.Trim()
    if (-not ($projects -contains $name)) { $projects.Add($name) }
}

function Update-Footer {
    $open = 0; $done = 0
    foreach ($t in $allTasks) { if ($t.Done) { $done++ } else { $open++ } }
    $countText.Text = "$open open  -  $done completed"
    if ($script:showCompleted) {
        $viewBtn.Content = "Active"; $viewBtn.ToolTip = "Show active actions"
        $clearBtn.Visibility = 'Visible'
    } else {
        $viewBtn.Content = "Done ($done)"; $viewBtn.ToolTip = "Show completed actions"
        $clearBtn.Visibility = 'Collapsed'
    }
}

function Refresh-View { $win.Dispatcher.BeginInvoke([Action]{ $script:view.Refresh() }) | Out-Null }

# --- Persistence ---
function Save-State {
    if ($script:suppressSave) { return }
    $data = [ordered]@{
        schema = 2
        tasks = @(foreach ($t in $allTasks) {
            @{
                text        = $t.Text
                project     = $t.Project
                done        = $t.Done
                due         = $(if ($t.Due)         { $t.Due.ToString('o') }         else { $null })
                completedAt = $(if ($t.CompletedAt) { $t.CompletedAt.ToString('o') } else { $null })
            }
        })
        window = @{
            left    = [double]$win.Left
            top     = [double]$win.Top
            width   = [double]$win.Width
            height  = [double]$win.Height
            topmost = [bool]$win.Topmost
        }
    }
    try { ($data | ConvertTo-Json -Depth 6) | Set-Content -Path $StateFile -Encoding UTF8 } catch {}
}

# Called whenever any task property changes
$onTaskChanged = {
    param($s, $e)
    Save-State
    Update-Footer
    if ($e.PropertyName -eq 'Done') { Refresh-View }
    if ($e.PropertyName -eq 'Project') { Add-Project $s.Project }
}

function Register-Task([TrackerTask]$item) {
    $allTasks.Add($item)
    $item.add_PropertyChanged($onTaskChanged)
}

function Load-State {
    if (-not (Test-Path $StateFile)) { Update-Footer; return }
    try {
        $data = Get-Content -Path $StateFile -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch { Update-Footer; return }

    if ($data.tasks) {
        foreach ($t in $data.tasks) {
            $item = New-Object TrackerTask
            $item.Text    = [string]$t.text
            if ($t.project) { $item.Project = [string]$t.project; Add-Project $item.Project }
            if ($t.due)         { try { $item.Due         = [datetime]::Parse($t.due) }         catch {} }
            if ($t.completedAt) { try { $item.CompletedAt = [datetime]::Parse($t.completedAt) } catch {} }
            $item.Done = [bool]$t.done     # set after CompletedAt so stored time is preserved
            Register-Task $item
        }
    }
    if ($data.window) {
        if ($data.window.width)  { $win.Width  = [double]$data.window.width }
        if ($data.window.height) { $win.Height = [double]$data.window.height }
        if ($data.window.left -ne $null -and $data.window.top -ne $null) {
            $win.WindowStartupLocation = 'Manual'
            $win.Left = [double]$data.window.left
            $win.Top  = [double]$data.window.top
        }
        # Honour a saved always-on-top choice only for state written by this version
        # (schema >= 2). Older files defaulted to always-on-top, so migrate them to
        # the new background default instead of restoring the old behaviour.
        if ($data.schema -and [int]$data.schema -ge 2) {
            if ($data.window.topmost -ne $null) { $win.Topmost = [bool]$data.window.topmost }
        } else {
            $win.Topmost = $false
        }
    }
    Update-Footer
}

# --- Add a task ---
function Add-Task {
    $text = $inputBox.Text.Trim()
    if ([string]::IsNullOrWhiteSpace($text)) { return }
    $item = New-Object TrackerTask
    $item.Text = $text
    $proj = ''
    if ($projInput.Text) { $proj = ([string]$projInput.Text).Trim() }
    if ($proj) { $item.Project = $proj; Add-Project $proj }
    if ($dueInput.SelectedDate) { $item.Due = [datetime]$dueInput.SelectedDate }
    $item.Done = $false
    Register-Task $item
    $inputBox.Clear()
    $dueInput.SelectedDate = $null
    # keep the project selected so several actions can be added to the same project
    if ($script:showCompleted) { $script:showCompleted = $false }  # jump to active so the new action shows
    Refresh-View
    Save-State
    Update-Footer
}

# --- Events ---
$inputBox.Add_KeyDown({
    param($s, $e)
    if ($e.Key -eq 'Return') { Add-Task; $e.Handled = $true }
})

# Drag the window by its header
$header.Add_MouseLeftButtonDown({
    param($s, $e)
    try { $win.DragMove() } catch {}
})

# Delete / reopen buttons inside rows (bubbled Click). Distinguished by Tag.
$list.AddHandler(
    [System.Windows.Controls.Primitives.ButtonBase]::ClickEvent,
    [System.Windows.RoutedEventHandler]{
        param($s, $e)
        $btn = $e.OriginalSource
        if ($btn -isnot [System.Windows.Controls.Button]) { return }   # ignore checkbox + datepicker buttons
        $item = $btn.DataContext
        if ($item -isnot [TrackerTask]) { return }
        switch ($btn.Tag) {
            'del' {
                $allTasks.Remove($item) | Out-Null
                Refresh-View; Save-State; Update-Footer
                $e.Handled = $true
            }
            'reopen' {
                $item.Done = $false      # undo completion -> PropertyChanged saves + refreshes
                $e.Handled = $true
            }
        }
    }
)

# View toggle (active <-> completed)
$viewBtn.Add_Click({
    $script:showCompleted = -not $script:showCompleted
    Refresh-View
    Update-Footer
})

# Pin / always-on-top toggle
$pinBtn.Add_Click({
    $win.Topmost = -not $win.Topmost
    $pinBtn.Opacity = $(if ($win.Topmost) { 1.0 } else { 0.4 })
    Save-State
})

# Permanently clear completed tasks
$clearBtn.Add_Click({
    for ($i = $allTasks.Count - 1; $i -ge 0; $i--) {
        if ($allTasks[$i].Done) { $allTasks.RemoveAt($i) }
    }
    Refresh-View; Save-State; Update-Footer
})

$closeBtn.Add_Click({ $win.Close() })

# Save position/size when moved or resized, and on close
$win.Add_LocationChanged({ Save-State })
$win.Add_SizeChanged({ Save-State })
$win.Add_Closing({ Save-State })

# --- Load saved state, then allow saving ---
Load-State
Refresh-View
$script:suppressSave = $false
if (-not $win.Topmost) { $pinBtn.Opacity = 0.4 }

# --- Show ---
[void]$win.ShowDialog()
