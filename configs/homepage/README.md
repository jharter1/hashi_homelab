# Homepage Dashboard Configuration

This directory contains the externalized configuration files for the Homepage dashboard service.

## Files

- **settings.yaml** - Main dashboard settings (theme, layout, background)
- **services.yaml** - Service definitions with links and widgets
- **widgets.yaml** - Dashboard widgets (weather, calendar, search, datetime)
- **bookmarks.yaml** - Bookmark links organized by category
- **docker.yaml** - Docker integration config (currently disabled)
- **custom.css** - Custom CSS styling for the dashboard

## Deployment

These files are automatically synced to `/mnt/nas/homepage/` on Nomad client nodes.

### Quick Update Workflow (Recommended)

To update the homepage configuration:

1. Edit files in this directory (`configs/homepage/`)
2. Run the update command:
   ```fish
   task homepage:update
   ```

That's it! This command syncs the configs and redeploys the service in one step.

### Individual Commands

If you need more control, use these individual tasks:

```fish
# Just sync configs (no redeploy)
task homepage:sync

# Just redeploy (no config sync)
task homepage:deploy

# Full ansible configure (slower, syncs all services)
task ansible:configure
```

### Manual Editing

Alternatively, you can edit files directly on a client node:

```fish
ssh ubuntu@10.0.0.60 "nano /mnt/nas/homepage/services.yaml"
task homepage:deploy
```

**Note:** If you edit files directly on the server, remember to copy them back to this directory to keep version control in sync.

## Widget API Keys

Some widgets require API keys to function. To enable them:

### Speedtest Tracker Widget
1. Log in to https://speedtest.lab.hartr.net
2. Go to Settings > API
3. Click "Create Token"
4. Copy the generated token
5. Edit `services.yaml`, find the Speedtest service, and uncomment the widget section
6. Replace `YOUR_API_KEY_HERE` with your token

### Audiobookshelf Widget
1. Log in to https://audiobookshelf.lab.hartr.net
2. Go to Settings > Users
3. Click on your user account
4. Click "Generate API Token"
5. Copy the generated token
6. Edit `services.yaml`, find the Audiobookshelf service, and uncomment the widget section
7. Replace `YOUR_API_KEY_HERE` with your token

### Calendar Widget

The calendar widget supports iCal format URLs. To add calendars:

1. Edit `widgets.yaml`
2. Find the `calendar:` section
3. Add your calendar URL(s):

**Google Calendar:**
- Open Google Calendar
- Click the three dots next to your calendar > Settings and sharing
- Scroll to "Integrate calendar"
- Copy the "Secret address in iCal format"
- Paste into the `url:` field

**iCloud Calendar:**
- Open Calendar app on Mac
- File > Export (save as .ics file)
- Host the file somewhere accessible (or use a public calendar URL)
- Paste URL into the `url:` field

**Other Services:**
- Most calendar services provide a "webcal://" or "https://" iCal URL
- Convert webcal:// to https:// if needed
- Paste into the `url:` field

## Troubleshooting

**Dashboard not updating:**
- Check if files were synced: `ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/homepage/"`
- Check nomad logs: `nomad alloc logs <alloc-id>`
- Verify Nomad service is running: `nomad job status homepage`

**Widget not showing:**
- Ensure API key is valid and not expired
- Check browser console for errors
- Verify the service URL is accessible from the homepage container

**Calendar not showing:**
- Verify the iCal URL is public and accessible
- Test URL in browser (should download .ics file)
- Check that the URL uses https:// not webcal://
