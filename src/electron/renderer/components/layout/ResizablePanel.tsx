import * as React from 'react'
import { cn } from '../../lib/utils'

interface ResizablePanelProps extends React.HTMLAttributes<HTMLDivElement> {
  children: React.ReactNode
}

export function ResizablePanel({ className, children, ...props }: ResizablePanelProps) {
  return (
    <div
      className={cn('flex flex-col overflow-hidden', className)}
      {...props}
    >
      {children}
    </div>
  )
}
