0 over one period.
			local t = 1 - math.abs(2 * phase - 1)
			prismatic.TargetPosition = t * travel
		end)
		mainDump:Add(conn)
	end

	return self
end

-- Types

export type SlideMode = Types.SlideMode
export type SlidableParams = Types.SlidableParams
export type Slidable = typeof(Slidable)

return Slidable
s