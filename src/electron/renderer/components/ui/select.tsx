import * as React from 'react'

interface SelectContextValue {
  value: string
  onValueChange: (value: string) => void
  open: boolean
  setOpen: (open: boolean) => void
}

const SelectContext = React.createContext<SelectContextValue | undefined>(undefined)

function useSelectContext() {
  const context = React.useContext(SelectContext)
  if (!context) {
    throw new Error('Select components must be used within Select')
  }
  return context
}

interface SelectProps {
  value: string
  onValueChange: (value: string) => void
  children: React.ReactNode
}

export function Select({ value, onValueChange, children }: SelectProps) {
  const [open, setOpen] = React.useState(false)

  return (
    <SelectContext.Provider value={{ value, onValueChange, open, setOpen }}>
      <div className="relative">{children}</div>
    </SelectContext.Provider>
  )
}

interface SelectTriggerProps {
  className?: string
  children: React.ReactNode
}

export function SelectTrigger({ className = '', children }: SelectTriggerProps) {
  const { open, setOpen } = useSelectContext()

  return (
    <button
      type="button"
      onClick={() => setOpen(!open)}
      className={`inline-flex items-center justify-between rounded border border-border bg-card px-3 py-1.5 text-xs text-foreground hover:bg-card-hover focus:outline-none focus:ring-2 focus:ring-primary ${className}`}
    >
      {children}
      <svg
        className={`ml-2 h-4 w-4 transition-transform ${open ? 'rotate-180' : ''}`}
        xmlns="http://www.w3.org/2000/svg"
        viewBox="0 0 20 20"
        fill="currentColor"
      >
        <path
          fillRule="evenodd"
          d="M5.293 7.293a1 1 0 011.414 0L10 10.586l3.293-3.293a1 1 0 111.414 1.414l-4 4a1 1 0 01-1.414 0l-4-4a1 1 0 010-1.414z"
          clipRule="evenodd"
        />
      </svg>
    </button>
  )
}

export function SelectValue({ placeholder }: { placeholder?: string }) {
  const { value } = useSelectContext()
  return <span>{value || placeholder}</span>
}

interface SelectContentProps {
  children: React.ReactNode
}

export function SelectContent({ children }: SelectContentProps) {
  const { open, setOpen } = useSelectContext()

  if (!open) return null

  return (
    <>
      <div className="fixed inset-0 z-40" onClick={() => setOpen(false)} />
      <div className="absolute z-50 mt-1 max-h-60 w-full overflow-auto rounded border border-border bg-card shadow-lg">
        {children}
      </div>
    </>
  )
}

interface SelectItemProps {
  value: string
  children: React.ReactNode
}

export function SelectItem({ value, children }: SelectItemProps) {
  const { value: selectedValue, onValueChange, setOpen } = useSelectContext()

  return (
    <button
      type="button"
      onClick={() => {
        onValueChange(value)
        setOpen(false)
      }}
      className={`w-full px-3 py-2 text-left text-xs hover:bg-card-hover ${
        selectedValue === value ? 'bg-primary/10 text-primary' : 'text-foreground'
      }`}
    >
      {children}
    </button>
  )
}
