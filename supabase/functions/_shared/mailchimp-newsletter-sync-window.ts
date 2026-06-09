export const MAILCHIMP_NEWSLETTER_SYNC_TIMEZONE = 'Australia/Sydney';
export const MAILCHIMP_NEWSLETTER_SYNC_TIMEZONE_LABEL = 'AEST/AEDT';
export const MAILCHIMP_NEWSLETTER_SYNC_WINDOW = {
  start_hour: 6,
  end_hour: 10,
};

export interface MailchimpNewsletterSyncWindowStatus {
  timezone: string;
  timezone_label: string;
  sync_window: typeof MAILCHIMP_NEWSLETTER_SYNC_WINDOW;
}

export function scheduleRateToCron(rate: string): string {
  switch (rate) {
    case '5 minutes':
      return '*/5 19-23 * * *';
    case '10 minutes':
      return '*/10 19-23 * * *';
    case '15 minutes':
      return '*/15 19-23 * * *';
    case '30 minutes':
      return '*/30 19-23 * * *';
    case '1 hour':
      return '0 19-23 * * *';
    default:
      throw new Error(`Unsupported schedule rate: ${rate}`);
  }
}

export function getMailchimpNewsletterSyncWindowStatus(): MailchimpNewsletterSyncWindowStatus {
  return {
    timezone: MAILCHIMP_NEWSLETTER_SYNC_TIMEZONE,
    timezone_label: MAILCHIMP_NEWSLETTER_SYNC_TIMEZONE_LABEL,
    sync_window: MAILCHIMP_NEWSLETTER_SYNC_WINDOW,
  };
}

export function getAustraliaSydneyHour(date = new Date()): number {
  const parts = new Intl.DateTimeFormat('en-AU', {
    timeZone: MAILCHIMP_NEWSLETTER_SYNC_TIMEZONE,
    hour: 'numeric',
    hourCycle: 'h23',
  }).formatToParts(date);
  const hour = Number(parts.find((part) => part.type === 'hour')?.value);
  if (!Number.isFinite(hour)) {
    throw new Error('Failed to resolve Australia/Sydney local hour');
  }
  return hour;
}

export function isWithinMailchimpNewsletterSyncWindow(date = new Date()): boolean {
  const hour = getAustraliaSydneyHour(date);
  return (
    hour >= MAILCHIMP_NEWSLETTER_SYNC_WINDOW.start_hour &&
    hour < MAILCHIMP_NEWSLETTER_SYNC_WINDOW.end_hour
  );
}
