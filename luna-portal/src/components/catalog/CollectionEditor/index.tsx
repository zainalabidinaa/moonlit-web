import { useState } from 'react';
import { supabase } from '../../../lib/supabase';
import { Modal } from '../../ui/Modal';
import { Button } from '../../ui/Button';
import { StepBasics } from './StepBasics';
import { StepContent } from './StepContent';
import { StepArtwork } from './StepArtwork';
import { StepReview } from './StepReview';
import type { Collection } from '../../../types';

type Draft = Partial<Collection> & { name: string };

const STEPS = ['Basics', 'Content', 'Artwork', 'Review'];

function toDraft(c: Collection | null): Draft {
  return c
    ? { ...c }
    : { name: '', view_mode: 'FOLLOW_LAYOUT', show_all_tab: false, focus_glow_enabled: true, pin_to_top: false };
}

interface Props {
  collection: Collection | null;
  onClose: () => void;
  onSaved: () => void;
}

export function CollectionEditor({ collection, onClose, onSaved }: Props) {
  const [step, setStep] = useState(0);
  const [draft, setDraft] = useState<Draft>(toDraft(collection));
  const [hasGroups, setHasGroups] = useState(false);
  const [saving, setSaving] = useState(false);
  const [savedId, setSavedId] = useState<string | null>(collection?.id ?? null);

  async function handleNext() {
    if (step === 0) {
      setSaving(true);
      if (savedId) {
        await supabase.from('collections').update({
          name: draft.name,
          pin_to_top: draft.pin_to_top ?? false,
          show_all_tab: draft.show_all_tab ?? false,
          focus_glow_enabled: draft.focus_glow_enabled !== false,
        }).eq('id', savedId);
      } else {
        const { data } = await supabase.from('collections').insert({
          name: draft.name,
          pin_to_top: draft.pin_to_top ?? false,
          show_all_tab: draft.show_all_tab ?? false,
          focus_glow_enabled: draft.focus_glow_enabled !== false,
          sort_order: 9999,
        }).select().single();
        if (data) setSavedId((data as Collection).id);
      }
      setSaving(false);
    }
    setStep(s => s + 1);
  }

  async function handleSave() {
    if (!savedId) return;
    setSaving(true);
    await supabase.from('collections').update({
      backdrop_image: draft.backdrop_image ?? null,
      view_mode: draft.view_mode ?? 'FOLLOW_LAYOUT',
    }).eq('id', savedId);
    setSaving(false);
    onSaved();
  }

  return (
    <Modal open onClose={onClose} title={collection ? `Edit: ${collection.name}` : 'New Collection'} width="max-w-2xl">
      <div className="px-6 pt-4 flex items-center gap-2">
        {STEPS.map((s, i) => (
          <div key={s} className="flex items-center gap-2">
            <div className={`w-6 h-6 rounded-full flex items-center justify-center text-xs font-semibold transition-colors ${i < step ? 'bg-accent text-white' : i === step ? 'bg-accent-light text-accent' : 'bg-border text-muted'}`}>
              {i < step ? '✓' : i + 1}
            </div>
            <span className={`text-xs ${i === step ? 'text-text font-medium' : 'text-muted'}`}>{s}</span>
            {i < STEPS.length - 1 && <div className="w-6 h-px bg-border" />}
          </div>
        ))}
      </div>

      <div className="p-6">
        {step === 0 && <StepBasics draft={draft} onChange={setDraft} />}
        {step === 1 && <StepContent collectionId={savedId} hasGroups={hasGroups} onHasGroupsChange={setHasGroups} />}
        {step === 2 && <StepArtwork draft={draft} onChange={setDraft} />}
        {step === 3 && <StepReview draft={draft} hasGroups={hasGroups} />}
      </div>

      <div className="px-6 pb-6 flex justify-between">
        <Button variant="ghost" onClick={step === 0 ? onClose : () => setStep(s => s - 1)}>
          {step === 0 ? 'Cancel' : 'Back'}
        </Button>
        {step < 3 ? (
          <Button onClick={handleNext} loading={saving}>Next</Button>
        ) : (
          <Button onClick={handleSave} loading={saving}>Save Collection</Button>
        )}
      </div>
    </Modal>
  );
}
