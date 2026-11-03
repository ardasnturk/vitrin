import { useCallback, useEffect, useRef, useState } from 'react';
import { api, fileUrl, type ReviewState } from '../api';
import { t } from '../i18n';
import { useBusy, useCli, useStudio } from '../store';
import { stageReason } from '../status';
import { Button, Card, fmtDate, Modal, Pill } from '../ui';

/** The review gallery (metadata/report.html) with approve and reject, exactly as `vitrin review --serve` offers it. */
export function Review() {
  const { state, run, toast } = useStudio();
  const busy = useBusy();
  const cli = useCli();
  const o = state.overview!;
  const [review, setReview] = useState<ReviewState | undefined>();
  const [loading, setLoading] = useState(false);
  const [confirm, setConfirm] = useState(false);
  const [frameKey, setFrameKey] = useState(0);
  const frame = useRef<HTMLIFrameElement>(null);

  const load = useCallback(async () => {
    setLoading(true);
    try {
      setReview(await api.review());
      setFrameKey((k) => k + 1);
    } catch (err) {
      toast((err as Error).message, 'err');
    } finally {
      setLoading(false);
    }
  }, [toast]);

  useEffect(() => {
    if (!state.job) void load();
  }, [state.changedTick, state.job, load]);

  const invalid = Boolean(o.validation && !o.validation.ok);

  const reject = useCallback(
    async (overallHash: string, rejections: Array<{ item: string; comment: string }>) => {
      try {
        const r = await api.reject(overallHash, rejections);
        toast(t('rejectionsSent', { n: r.rejected }), 'ok');
      } catch (err) {
        toast((err as Error).message, 'err');
      }
      await load();
    },
    [load, toast],
  );

  // The server serves the gallery with a sandbox CSP (no origin, no API; an iframe `sandbox` attribute would do the same
  // but some embedded browsers refuse such frames): its buttons post the decision here, and the Studio records it with
  // its session token. Only messages from this page's own frame count.
  useEffect(() => {
    const onMessage = (e: MessageEvent) => {
      if (!frame.current || e.source !== frame.current.contentWindow) return;
      const d = (typeof e.data === 'object' && e.data !== null ? e.data : {}) as { type?: unknown; overallHash?: unknown; rejections?: unknown };
      if (d.type !== 'vitrin-approve' && d.type !== 'vitrin-reject') return;
      if (!review || d.overallHash !== review.overallHash) {
        toast(t('errFilesChanged'), 'err');
        void load();
        return;
      }
      if (d.type === 'vitrin-approve') setConfirm(true);
      else if (Array.isArray(d.rejections)) {
        const rejections = d.rejections.filter((r): r is { item: string; comment: string } => typeof r === 'object' && r !== null && typeof (r as { item?: unknown }).item === 'string' && typeof (r as { comment?: unknown }).comment === 'string');
        if (rejections.length) void reject(review.overallHash, rejections);
      }
    };
    window.addEventListener('message', onMessage);
    return () => window.removeEventListener('message', onMessage);
  }, [review, load, reject, toast]);

  const approve = async () => {
    if (!review) return;
    try {
      await api.approve(review.overallHash);
      toast(t('approved'), 'ok');
      setConfirm(false);
      await load();
    } catch (err) {
      toast((err as Error).message, 'err');
      await load();
    }
  };

  return (
    <div className="page">
      <header>
        <h2>{t('review')}</h2>
        <p>{t('reviewIntro')}</p>
      </header>
      <div className="row wrap" style={{ marginBottom: 14 }}>
        {review?.approval.ok && o.approval?.valid ? (
          <Pill tone="ok">
            {t('approved')} · {fmtDate(o.approval?.approvedAt)}
          </Pill>
        ) : review?.approval.ok && o.approval ? (
          <span className="text-err small">{t('approvalInvalid', { reason: stageReason({ id: 'review', status: 'blocked', reason: o.approval.problem }, o) })}</span>
        ) : (
          <Pill tone="warn">{review?.approval.reason ?? t('notApproved')}</Pill>
        )}
        {o.validation && <Pill tone={o.validation.ok ? 'ok' : 'err'}>{o.validation.ok ? t('validationOk') : t('validationErrors', { n: o.validation.counts.error })}</Pill>}
        {review && (
          <span className="dim mono small">
            {t('overallHash')} {review.overallHash.slice(0, 12)}
          </span>
        )}
        <span className="grow" />
        <Button disabled={busy || loading} title={cli('vitrin validate')} onClick={() => run('validate')}>
          {t('stageValidate')}
        </Button>
        <Button disabled={busy || loading} onClick={() => load()}>
          {t('rebuild')}
        </Button>
        <Button onClick={() => window.open(fileUrl('metadata/report.html'), '_blank')} disabled={!o.files.report}>
          {t('openGallery')}
        </Button>
        <Button kind="primary" disabled={busy || loading || !review || review.approval.ok || invalid} onClick={() => setConfirm(true)}>
          {t('approveAll')}
        </Button>
      </div>
      {invalid && !review?.approval.ok && <div className="dim small" style={{ marginBottom: 12 }}>{t('approveNeedsValid')}</div>}
      {review && (
        <Card className="tight" title={t('items', { n: review.items.length })}>
          <div className="row wrap">
            {review.summary.map((l, i) => (
              <span key={i} className="pill">
                {l}
              </span>
            ))}
          </div>
        </Card>
      )}
      <div style={{ marginTop: 12 }}>{o.files.report ? <iframe key={frameKey} ref={frame} className="gallery-frame" src={fileUrl('metadata/report.html', frameKey)} title="review gallery" /> : <div className="empty">{t('nothingYet')}</div>}</div>
      {confirm && review && (
        <Modal title={t('approveAll')} onClose={() => setConfirm(false)}>
          <div className="stack">
            <p>{t('reviewIntro')}</p>
            <ul className="issues">
              {review.summary.map((l, i) => (
                <li key={i}>{l}</li>
              ))}
            </ul>
            <div className="dim mono small">
              {t('overallHash')} {review.overallHash}
            </div>
            <div className="row">
              <Button kind="primary" onClick={approve}>
                {t('approveAll')}
              </Button>
              <Button onClick={() => setConfirm(false)}>{t('cancel')}</Button>
            </div>
          </div>
        </Modal>
      )}
    </div>
  );
}
