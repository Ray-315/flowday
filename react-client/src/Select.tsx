import { Children, isValidElement, useCallback, useState, type ReactNode } from 'react';
import * as SelectPrimitive from '@radix-ui/react-select';
import { Check, ChevronLeft } from './icons';

interface SelectProps {
  children: ReactNode;
  value?: string | number;
  onChange?: (event: { target: { value: string } }) => void;
  disabled?: boolean;
  id?: string;
  name?: string;
  required?: boolean;
  className?: string;
  'aria-label'?: string;
  'aria-labelledby'?: string;
}

/** Shared single-choice control. Keeps the existing value-oriented change API. */
export function Select({ children, value, onChange, disabled, name, required, className, ...labelProps }: SelectProps) {
  const [portalContainer, setPortalContainer] = useState<HTMLElement | null>(null);
  const triggerRef = useCallback((node: HTMLButtonElement | null) => {
    // A native modal dialog makes body portals inert and hides them below its top layer.
    setPortalContainer(node?.closest('dialog') ?? null);
  }, []);
  const options = Children.toArray(children).flatMap(child => {
    if (!isValidElement<{ value?: string | number; children?: ReactNode; disabled?: boolean }>(child)) return [];
    const text = Children.toArray(child.props.children).join('');
    return [{ value: String(child.props.value ?? text), text, disabled: child.props.disabled }];
  });
  // Radix reserves the empty string for its placeholder; our forms use it as a real option.
  let emptyValue = '__flowday_empty__';
  while (options.some(option => option.value === emptyValue)) emptyValue += '_';
  const selected = String(value ?? options[0]?.value ?? '');
  return (
    <SelectPrimitive.Root
      value={options.length ? selected || emptyValue : ''}
      onValueChange={next => onChange?.({ target: { value: next === emptyValue ? '' : next } })}
      disabled={disabled || options.length === 0}
      name={name}
      required={required}
    >
      <SelectPrimitive.Trigger ref={triggerRef} {...labelProps} className={`select-trigger ${className ?? ''}`}>
        <SelectPrimitive.Value placeholder={options.length ? "请选择" : "暂无选项"} />
        <SelectPrimitive.Icon className="select-chevron"><ChevronLeft size={16} /></SelectPrimitive.Icon>
      </SelectPrimitive.Trigger>
      <SelectPrimitive.Portal container={portalContainer}>
        <SelectPrimitive.Content className="select-menu" position="popper" sideOffset={6} collisionPadding={12}>
          <SelectPrimitive.ScrollUpButton className="select-scroll"><ChevronLeft size={14} /></SelectPrimitive.ScrollUpButton>
          <SelectPrimitive.Viewport className="select-options">
            {options.map(option => (
              <SelectPrimitive.Item key={option.value} value={option.value || emptyValue} disabled={option.disabled} className="select-option">
                <SelectPrimitive.ItemText>{option.text}</SelectPrimitive.ItemText>
                <SelectPrimitive.ItemIndicator className="select-check"><Check size={16} /></SelectPrimitive.ItemIndicator>
              </SelectPrimitive.Item>
            ))}
          </SelectPrimitive.Viewport>
          <SelectPrimitive.ScrollDownButton className="select-scroll select-scroll-down"><ChevronLeft size={14} /></SelectPrimitive.ScrollDownButton>
        </SelectPrimitive.Content>
      </SelectPrimitive.Portal>
    </SelectPrimitive.Root>
  );
}
